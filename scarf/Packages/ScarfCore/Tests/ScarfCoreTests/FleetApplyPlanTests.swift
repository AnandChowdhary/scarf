import Testing
import Foundation
@testable import ScarfCore

/// Pure coverage for `FleetApplyPlan` — applicable-field gating, per-field
/// dispositions (incl. the additive board guard), and the boundary-aware
/// cron-prompt path rewriter that the user opted into for cross-host cron
/// apply.
@Suite struct FleetApplyPlanTests {

    static func materialization(
        serverId: String,
        name: String = "Proj",
        rootPath: String = "/p",
        modelPresetId: String? = nil,
        board: String? = nil,
        cronJobIds: [String] = []
    ) -> FleetMaterialization {
        FleetMaterialization(
            serverId: serverId,
            serverDisplayName: serverId,
            project: ScarfProject(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                name: name,
                rootPath: rootPath,
                modelPresetId: modelPresetId,
                board: board,
                cronJobIds: cronJobIds
            )
        )
    }

    // MARK: - Applicable fields

    @Test func applicableFieldsReflectsSourceConfig() {
        let bare = ScarfProject(name: "Bare", rootPath: "/b")
        #expect(FleetApplyPlan.applicableFields(source: bare).isEmpty)

        let full = ScarfProject(name: "Full", rootPath: "/f",
                                modelPresetId: "preset", board: "scarf:f", cronJobIds: ["j1"])
        #expect(FleetApplyPlan.applicableFields(source: full) == [.modelPreset, .board, .cron])
    }

    // MARK: - Dispositions

    @Test func modelPresetApplyAndSkip() {
        let source = Self.materialization(serverId: "src", modelPresetId: "fast")
        let needsIt = Self.materialization(serverId: "a", modelPresetId: nil)
        let hasIt = Self.materialization(serverId: "b", modelPresetId: "fast")

        let plan = FleetApplyPlan.make(source: source, targets: [needsIt, hasIt], fields: [.modelPreset])
        #expect(plan.targets[0].actions.first?.disposition.isApply == true)
        #expect(plan.targets[1].actions.first?.disposition == .skip("already matches"))
    }

    @Test func boardIsAdditiveNeverClobbers() {
        let source = Self.materialization(serverId: "src", board: "scarf:src")
        let empty = Self.materialization(serverId: "a", board: nil)
        let different = Self.materialization(serverId: "b", board: "scarf:other")
        let same = Self.materialization(serverId: "c", board: "scarf:src")

        let plan = FleetApplyPlan.make(source: source, targets: [empty, different, same], fields: [.board])
        #expect(plan.targets[0].actions.first?.disposition.isApply == true)        // empty → set
        // Different existing board is KEPT (protects the target's tasks).
        if case .skip(let reason) = plan.targets[1].actions.first?.disposition {
            #expect(reason.contains("kept"))
        } else {
            Issue.record("expected board skip on host with a different existing board")
        }
        #expect(plan.targets[2].actions.first?.disposition == .skip("already matches"))
    }

    @Test func cronApplyWhenSourceHasJobs() {
        let source = Self.materialization(serverId: "src", cronJobIds: ["j1", "j2"])
        let target = Self.materialization(serverId: "a")
        let plan = FleetApplyPlan.make(source: source, targets: [target], fields: [.cron])
        #expect(plan.targets[0].actions.first?.disposition.isApply == true)
        #expect(plan.targets[0].actions.first?.disposition.detail.contains("2") == true)
    }

    @Test func effectiveTargetsFiltersNoOpHosts() {
        let source = Self.materialization(serverId: "src", modelPresetId: "fast")
        let noop = Self.materialization(serverId: "a", modelPresetId: "fast")   // already matches
        let change = Self.materialization(serverId: "b", modelPresetId: nil)
        let plan = FleetApplyPlan.make(source: source, targets: [noop, change], fields: [.modelPreset])
        #expect(plan.effectiveTargets.map(\.serverId) == ["b"])
    }

    @Test func planCarriesTargetRootForRewrite() {
        let source = Self.materialization(serverId: "src", rootPath: "/src/proj", cronJobIds: ["j"])
        let target = Self.materialization(serverId: "a", rootPath: "/tgt/proj")
        let plan = FleetApplyPlan.make(source: source, targets: [target], fields: [.cron])
        #expect(plan.sourceRootPath == "/src/proj")
        #expect(plan.targets[0].rootPath == "/tgt/proj")
    }

    // MARK: - Cron prompt rewriting

    @Test func rewriteReplacesPathPrefix() {
        let prompt = "Read /src/proj/.scarf/config.json and update /src/proj/status.md"
        let out = FleetApplyPlan.rewriteCronPrompt(prompt, sourceRoot: "/src/proj", targetRoot: "/tgt/proj")
        #expect(out == "Read /tgt/proj/.scarf/config.json and update /tgt/proj/status.md")
    }

    @Test func rewriteReplacesBareRootAtBoundaries() {
        #expect(FleetApplyPlan.rewriteCronPrompt("cd /src/proj", sourceRoot: "/src/proj", targetRoot: "/tgt/proj") == "cd /tgt/proj")
        #expect(FleetApplyPlan.rewriteCronPrompt("cd /src/proj && go", sourceRoot: "/src/proj", targetRoot: "/tgt/proj") == "cd /tgt/proj && go")
        #expect(FleetApplyPlan.rewriteCronPrompt("at \"/src/proj\"", sourceRoot: "/src/proj", targetRoot: "/tgt/proj") == "at \"/tgt/proj\"")
    }

    @Test func rewriteDoesNotTouchPrefixCollisions() {
        // /src/proj must NOT match inside /src/proj2 — boundary check.
        let prompt = "use /src/proj2/data and /src/projector"
        let out = FleetApplyPlan.rewriteCronPrompt(prompt, sourceRoot: "/src/proj", targetRoot: "/tgt/proj")
        #expect(out == prompt)
    }

    @Test func rewriteHandlesTrailingSlashAndNoOp() {
        // Source root with trailing slash normalizes the same.
        #expect(FleetApplyPlan.rewriteCronPrompt("/src/proj/x", sourceRoot: "/src/proj/", targetRoot: "/tgt/proj") == "/tgt/proj/x")
        // No occurrence → unchanged.
        #expect(FleetApplyPlan.rewriteCronPrompt("nothing here", sourceRoot: "/src/proj", targetRoot: "/tgt/proj") == "nothing here")
        // Empty source → unchanged.
        #expect(FleetApplyPlan.rewriteCronPrompt("/src/proj", sourceRoot: "", targetRoot: "/tgt") == "/src/proj")
        // Same root → unchanged.
        #expect(FleetApplyPlan.rewriteCronPrompt("/src/proj", sourceRoot: "/src/proj", targetRoot: "/src/proj") == "/src/proj")
    }

    @Test func rewriteReplacesEveryOccurrence() {
        let prompt = "/src/proj /src/proj /src/proj"
        let out = FleetApplyPlan.rewriteCronPrompt(prompt, sourceRoot: "/src/proj", targetRoot: "/x")
        #expect(out == "/x /x /x")
    }
}
