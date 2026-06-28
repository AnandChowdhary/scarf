import Foundation

/// A config field that "apply to fleet" can push from a source project's
/// host onto other hosts (Phase-1 item #4, config-as-policy).
///
/// Only **host-portable** config is here. Model preset and board are pure
/// references (a preset UUID, a tenant slug) with no embedded paths, so
/// they copy cleanly. Cron is host-COUPLED — its prompts embed the
/// source host's absolute project path — so cron apply rewrites those
/// paths to the target's root (`FleetApplyPlan.rewriteCronPrompt`). Tool/
/// skill scoping is deferred upstream (hermes-agent#45958) and so is not
/// a field here.
public enum FleetApplyField: String, Sendable, CaseIterable {
    case modelPreset
    case board
    case cron

    public var label: String {
        switch self {
        case .modelPreset: return "Model preset"
        case .board:       return "Board"
        case .cron:        return "Cron jobs"
        }
    }
}

/// A computed, previewable plan for applying a source project's config to
/// a set of target hosts. **Pure** — built from records only, no I/O. The
/// Mac-target `FleetApplyExecutor` consumes it and performs the writes,
/// reporting actual results back; this type is the intent + the preview.
///
/// Each target carries a per-field `Disposition` (`apply` with a summary,
/// or `skip` with a reason) so the user sees exactly what will change —
/// and what *won't*, like a board kept to protect its existing tasks —
/// before committing.
public struct FleetApplyPlan: Sendable, Equatable {

    /// The stable id being applied across the fleet.
    public let projectID: UUID
    /// `ServerContext.id.uuidString` of the source (the host whose config
    /// is being pushed).
    public let sourceServerId: String
    /// The source host's project root — the path that cron-prompt
    /// rewriting replaces with each target's root.
    public let sourceRootPath: String
    public var targets: [Target]

    public init(projectID: UUID, sourceServerId: String, sourceRootPath: String, targets: [Target]) {
        self.projectID = projectID
        self.sourceServerId = sourceServerId
        self.sourceRootPath = sourceRootPath
        self.targets = targets
    }

    public struct Target: Sendable, Equatable, Identifiable {
        public let serverId: String
        public let serverDisplayName: String?
        /// The target host's own project root — where cron prompts get
        /// rewritten to, and the path the manifest writers address.
        public let rootPath: String
        public var actions: [Action]

        public init(serverId: String, serverDisplayName: String?, rootPath: String, actions: [Action]) {
            self.serverId = serverId
            self.serverDisplayName = serverDisplayName
            self.rootPath = rootPath
            self.actions = actions
        }

        public var id: String { serverId }

        /// True when at least one field will actually be written.
        public var willChange: Bool { actions.contains { $0.disposition.isApply } }
    }

    public struct Action: Sendable, Equatable {
        public let field: FleetApplyField
        public let disposition: Disposition

        public init(field: FleetApplyField, disposition: Disposition) {
            self.field = field
            self.disposition = disposition
        }
    }

    public enum Disposition: Sendable, Equatable {
        /// Will write; payload is a short human summary ("set board scarf:x").
        case apply(String)
        /// Won't write; payload is the reason ("already matches",
        /// "target already has a board").
        case skip(String)

        public var isApply: Bool { if case .apply = self { return true }; return false }

        public var detail: String {
            switch self {
            case .apply(let s): return s
            case .skip(let s):  return s
            }
        }
    }

    /// Targets that will actually change at least one field.
    public var effectiveTargets: [Target] { targets.filter(\.willChange) }

    // MARK: - Planning (pure)

    /// Which fields the SOURCE actually carries a value for — the only
    /// fields it makes sense to offer in the UI. You can't push a model
    /// preset you don't have, a board you haven't minted, or cron jobs
    /// that don't exist.
    public static func applicableFields(source: ScarfProject) -> Set<FleetApplyField> {
        var fields: Set<FleetApplyField> = []
        if let p = source.modelPresetId, !p.isEmpty { fields.insert(.modelPreset) }
        if let b = source.board, !b.isEmpty { fields.insert(.board) }
        if !source.cronJobIds.isEmpty { fields.insert(.cron) }
        return fields
    }

    /// Build the plan: for each target, decide each chosen field's
    /// disposition. Pure — decides from the records alone. (The executor
    /// does the finer-grained per-cron-job idempotency at write time; the
    /// plan's cron line is the intent.)
    public static func make(
        source: FleetMaterialization,
        targets: [FleetMaterialization],
        fields: Set<FleetApplyField>
    ) -> FleetApplyPlan {
        let src = source.project
        let planTargets: [Target] = targets.map { t in
            // Stable field order via allCases.
            let actions: [Action] = FleetApplyField.allCases
                .filter { fields.contains($0) }
                .map { Action(field: $0, disposition: disposition($0, source: src, target: t.project)) }
            return Target(
                serverId: t.serverId,
                serverDisplayName: t.serverDisplayName,
                rootPath: t.project.rootPath,
                actions: actions
            )
        }
        return FleetApplyPlan(
            projectID: src.id,
            sourceServerId: source.serverId,
            sourceRootPath: src.rootPath,
            targets: planTargets
        )
    }

    /// Decide one field's disposition for one target. The board rule is
    /// **additive**: a target that already has a (non-matching) tenant is
    /// kept as-is — overwriting would orphan its existing board tasks.
    /// Model is overwrite-safe (reversible re-bind). Cron is recreate-on-
    /// target (the executor skips by name for idempotency).
    static func disposition(_ field: FleetApplyField, source: ScarfProject, target: ScarfProject) -> Disposition {
        switch field {
        case .modelPreset:
            guard let preset = source.modelPresetId, !preset.isEmpty else {
                return .skip("source has no model preset bound")
            }
            if target.modelPresetId == preset { return .skip("already matches") }
            return .apply("set model preset")

        case .board:
            guard let board = source.board, !board.isEmpty else {
                return .skip("source has no board")
            }
            if let tb = target.board, !tb.isEmpty {
                return tb == board
                    ? .skip("already matches")
                    : .skip("target already has a board (kept to protect its tasks)")
            }
            return .apply("set board \(board)")

        case .cron:
            let count = source.cronJobIds.count
            guard count > 0 else { return .skip("source has no project cron jobs") }
            return .apply("recreate up to \(count) cron job\(count == 1 ? "" : "s")")
        }
    }

    // MARK: - Cron prompt path rewriting (pure)

    /// Rewrite occurrences of the source host's project root in a cron
    /// prompt to the target host's root. The same logical project lives
    /// at different absolute paths per host, and Hermes runs cron jobs
    /// with no CWD — so a fully-qualified prompt copied verbatim would
    /// point at the *source* host's filesystem. This swaps the root.
    ///
    /// **Boundary-aware (conservative).** The root is only replaced when
    /// the character after the match is a path boundary — `/`, whitespace,
    /// a quote, or end-of-string — so a root that's a *prefix* of an
    /// unrelated path (`/work/proj` vs `/work/proj2`) is left intact, and
    /// unrelated text is never corrupted. It can under-replace on exotic
    /// punctuation (`…/proj.`), but the bias is deliberate: never mangle a
    /// prompt, even at the cost of missing a rare boundary.
    public static func rewriteCronPrompt(_ prompt: String, sourceRoot: String, targetRoot: String) -> String {
        let s = normalizeRoot(sourceRoot)
        let t = normalizeRoot(targetRoot)
        guard !s.isEmpty, s != t else { return prompt }

        var result = ""
        var searchStart = prompt.startIndex
        while let range = prompt.range(of: s, range: searchStart..<prompt.endIndex) {
            result += prompt[searchStart..<range.lowerBound]
            let isBoundary: Bool
            if range.upperBound == prompt.endIndex {
                isBoundary = true
            } else {
                let next = prompt[range.upperBound]
                isBoundary = next == "/" || next == " " || next == "\t"
                    || next == "\n" || next == "\"" || next == "'"
            }
            // On a real boundary, swap in the target root; otherwise
            // re-emit the *matched* slice (not the normalized source) so a
            // canonical-but-not-byte-identical match is preserved verbatim.
            result += isBoundary ? t : String(prompt[range])
            searchStart = range.upperBound
        }
        result += prompt[searchStart..<prompt.endIndex]
        return result
    }

    /// Strip trailing slashes (keep a lone "/") and surrounding
    /// whitespace so the prefix match is path-clean.
    private static func normalizeRoot(_ path: String) -> String {
        var s = path.trimmingCharacters(in: .whitespaces)
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Build the `hermes cron create` argv for copying `job` from the source
    /// host to a target host, forwarding only the flags that target's `caps`
    /// understand and rewriting project paths source→target.
    ///
    /// **Capability gating (mixed-version fleets).** `--deliver all` is a
    /// v0.14+ value (`caps.hasCronDeliverAll`): on an older target argparse
    /// rejects it and the whole `cron create` fails, so we DROP `--deliver`
    /// (the job is still created, falling back to Hermes's default delivery)
    /// and report it via the returned `droppedDeliverAll` so the caller can
    /// surface the downgrade. The match is exact — `"all"` is Hermes's single
    /// v0.14 fan-out sentinel; a specific platform (`discord`, `discord:chan`,
    /// `telegram:chat`) is baseline and always forwarded unchanged. `--workdir`
    /// is a v0.12+ flag (`caps.hasCronWorkdir`); it's path-rewritten
    /// source→target like the prompt, and omitted on a pre-v0.12 target (which
    /// also matches the pre-existing behavior of dropping workdir entirely).
    ///
    /// Pass `.empty` caps to be conservative (drop the version-gated flags) —
    /// e.g. when the target's `hermes --version` probe failed.
    ///
    /// NOT forwarded, each with a concrete reason (all dropped today too):
    /// - `repeat` — not modeled on `HermesCronJob` (a loaded job carries no
    ///   repeat count; only the template spec does), so nothing to forward.
    /// - `context_from` — YAML-only; Hermes exposes no `--context-from` CLI flag.
    /// - `pre_run_script` / `no_agent` — `pre_run_script` is a FILE PATH on the
    ///   source host that fleet-apply does not replicate to the target, so
    ///   forwarding `--script` would dangle. `no_agent` (script-only) jobs are
    ///   therefore skipped + surfaced by the caller, not built here. A
    ///   script-replicating copy is tracked separately.
    /// - `model` — the source's model reference may not be configured on the
    ///   target (would error at create or first run).
    /// - `silent` — JSON-only field; `cron create` has no flag for it.
    /// `schedule` is passed in resolved (the caller owns the
    /// cron-expr/run-at/display fallback).
    public static func cronCreateArgs(
        copying job: HermesCronJob,
        schedule: String,
        caps: HermesCapabilities,
        sourceRoot: String,
        targetRoot: String
    ) -> (args: [String], droppedDeliverAll: Bool) {
        var args = ["cron", "create", "--name", job.name]
        var droppedDeliverAll = false

        if let deliver = job.deliver, !deliver.isEmpty {
            if deliver == "all" && !caps.hasCronDeliverAll {
                droppedDeliverAll = true
            } else {
                args += ["--deliver", deliver]
            }
        }
        for skill in job.skills ?? [] where !skill.isEmpty { args += ["--skill", skill] }
        if let workdir = job.workdir, !workdir.isEmpty, caps.hasCronWorkdir {
            args += ["--workdir", rewriteCronPrompt(workdir, sourceRoot: sourceRoot, targetRoot: targetRoot)]
        }
        args.append(schedule)  // positional schedule
        args.append(rewriteCronPrompt(job.prompt, sourceRoot: sourceRoot, targetRoot: targetRoot))  // positional prompt
        return (args, droppedDeliverAll)
    }
}
