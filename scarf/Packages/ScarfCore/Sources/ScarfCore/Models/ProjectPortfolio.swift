import Foundation

/// The fleet/portfolio dimension — the same logical project grouped
/// across every server it's materialized on. This is the capability a
/// per-gateway client structurally cannot offer (Phase-1 item #4).
///
/// **Grouping key is `ScarfProject.id`** — the stable UUID minted once and
/// stored repo-resident in `<root>/.scarf/project.json`. Because the
/// record travels with the repo, the same project cloned to two hosts
/// shares the id and groups together; two unrelated projects that merely
/// share a *name* do not. Path and name are deliberately NOT the key
/// (paths differ per host by design — that's `HostBinding.rootPath`).
///
/// Pure value type. `ProjectPortfolio.build(from:)` is the testable
/// grouping core; `FleetService.portfolio()` is the disk-backed gather
/// that feeds it. No I/O lives here.
public struct ProjectPortfolio: Sendable, Equatable {

    /// One entry per distinct stable id seen across the fleet, sorted by
    /// display name (case-insensitive) then id for stable ordering.
    public var projects: [FleetProject]

    public init(projects: [FleetProject]) {
        self.projects = projects
    }

    /// The fleet entry for a given stable id, if the id is live anywhere
    /// in the fleet. The cockpit Fleet panel uses this to scope the
    /// portfolio to the project the user is looking at.
    public func project(id: UUID) -> FleetProject? {
        projects.first { $0.id == id }
    }

    /// Projects materialized on more than one host — the ones for which
    /// "apply to fleet" and drift are meaningful.
    public var multiHostProjects: [FleetProject] {
        projects.filter(\.isMultiHost)
    }
}

// MARK: - Fleet project

/// One logical project across the fleet: its stable id, a canonical
/// display name, every host it's materialized on, and the per-field
/// config disagreement between those hosts.
public struct FleetProject: Sendable, Equatable, Identifiable {

    /// Stable id (`ScarfProject.id`) — the grouping key.
    public let id: UUID

    /// Canonical display name. Hosts can disagree (e.g. a rename on one
    /// host only); we surface the most-recently-updated host's name and
    /// expose the disagreement via `drift.has(.name)`.
    public var name: String

    /// One entry per host the id is live on, sorted by `serverId` for a
    /// stable render order across reloads.
    public var materializations: [FleetMaterialization]

    /// Per-field disagreement across `materializations`. Empty for a
    /// single-host project (nothing to disagree with).
    public var drift: FleetDrift

    public init(
        id: UUID,
        name: String,
        materializations: [FleetMaterialization],
        drift: FleetDrift
    ) {
        self.id = id
        self.name = name
        self.materializations = materializations
        self.drift = drift
    }

    /// True when the project lives on more than one host.
    public var isMultiHost: Bool { materializations.count > 1 }

    /// The materialization on a given server, if any.
    public func materialization(serverId: String) -> FleetMaterialization? {
        materializations.first { $0.serverId == serverId }
    }
}

/// One host's materialization of a fleet project — where the stable id is
/// live, and the full record on that host (the source for any per-host
/// facet the UI renders).
public struct FleetMaterialization: Sendable, Equatable, Identifiable {

    /// `ServerContext.id.uuidString` — matches `HostBinding.serverId` and
    /// the well-known local id.
    public let serverId: String

    /// Resolved server display name, when the caller could map
    /// `serverId` → a known `ServerContext`. `nil` → the UI falls back to
    /// a short id prefix (a host that's in a record's `hostBindings` but
    /// no longer in the user's server registry).
    public var serverDisplayName: String?

    /// The full `ScarfProject` record as it exists on this host. Carries
    /// this host's `rootPath`, `modelPresetId`, `board`, `cronJobIds`,
    /// etc. — the per-host config that drift compares and "apply to
    /// fleet" overwrites.
    public var project: ScarfProject

    public init(
        serverId: String,
        serverDisplayName: String?,
        project: ScarfProject
    ) {
        self.serverId = serverId
        self.serverDisplayName = serverDisplayName
        self.project = project
    }

    public var id: String { serverId }
}

// MARK: - Drift

/// Which policy-relevant config fields disagree across a fleet project's
/// host materializations. A field "drifts" when two hosts hold different
/// values for it. Always empty for a single-host project.
///
/// Drift is the read-side signal that motivates "apply to fleet": it
/// shows the user *where* hosts have diverged before they push a source
/// project's config out as policy.
public struct FleetDrift: Sendable, Equatable {

    public enum Field: String, Sendable, CaseIterable, Comparable {
        /// Display name disagrees (a rename that didn't propagate).
        case name
        /// Bound model preset id disagrees (incl. bound-vs-default).
        case modelPreset
        /// Kanban board / tenant slug disagrees.
        case board
        /// Count of project-attributed cron jobs disagrees. Compared by
        /// COUNT, not by id — `cronJobIds` are host-local job ids that
        /// differ per host even for the same logical jobs, so id-equality
        /// would always read as drift. Count is the honest coarse signal.
        case cron
        /// MEMORY.md namespace disagrees.
        case memoryNamespace
        /// The set of registered mini-app ids disagrees.
        case miniApps

        public static func < (lhs: Field, rhs: Field) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The fields that differ across hosts.
    public var fields: Set<Field>

    public init(fields: Set<Field> = []) {
        self.fields = fields
    }

    public var isEmpty: Bool { fields.isEmpty }

    public func has(_ field: Field) -> Bool { fields.contains(field) }

    /// Fields in a stable, display-friendly order.
    public var sortedFields: [Field] { fields.sorted() }

    /// Compute drift across a group's materializations. A single
    /// materialization (or zero) never drifts. Pure.
    public static func compute(_ materializations: [FleetMaterialization]) -> FleetDrift {
        guard materializations.count > 1 else { return FleetDrift() }
        let projects = materializations.map(\.project)
        var fields: Set<Field> = []

        if disagrees(projects.map(\.name)) { fields.insert(.name) }
        if disagrees(projects.map(\.modelPresetId)) { fields.insert(.modelPreset) }
        if disagrees(projects.map(\.board)) { fields.insert(.board) }
        if disagrees(projects.map { $0.cronJobIds.count }) { fields.insert(.cron) }
        if disagrees(projects.map(\.memoryNamespace)) { fields.insert(.memoryNamespace) }
        if disagrees(projects.map { Set($0.miniApps.map(\.id)) }) { fields.insert(.miniApps) }

        return FleetDrift(fields: fields)
    }

    /// True when `values` holds more than one distinct value.
    private static func disagrees<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count > 1
    }
}

// MARK: - Grouping (pure)

extension ProjectPortfolio {

    /// One host's contribution to the fleet: the server it came from and
    /// every `ScarfProject` that host knows about. The disk-backed gather
    /// in `FleetService.portfolio()` produces one of these per context;
    /// tests construct them directly to exercise grouping without I/O.
    public struct HostProjects: Sendable {
        public var serverId: String
        public var serverDisplayName: String?
        public var projects: [ScarfProject]

        public init(serverId: String, serverDisplayName: String?, projects: [ScarfProject]) {
            self.serverId = serverId
            self.serverDisplayName = serverDisplayName
            self.projects = projects
        }
    }

    /// Group a flat set of per-host project lists into the portfolio:
    /// bucket by `ScarfProject.id`, build one `FleetProject` per id with
    /// its materializations + computed drift. Pure — no I/O, no clock.
    ///
    /// Within a single host, if the same id appears twice (shouldn't
    /// happen — one record per path — but be defensive), the first wins.
    /// The canonical name is taken from the most-recently-updated
    /// materialization so a stale rename on one host doesn't win.
    public static func build(from hosts: [HostProjects]) -> ProjectPortfolio {
        // id → [materialization], preserving first-seen-per-host.
        var groups: [UUID: [FleetMaterialization]] = [:]
        var order: [UUID] = []

        for host in hosts {
            var seenOnThisHost: Set<UUID> = []
            for project in host.projects {
                guard seenOnThisHost.insert(project.id).inserted else { continue }
                let m = FleetMaterialization(
                    serverId: host.serverId,
                    serverDisplayName: host.serverDisplayName,
                    project: project
                )
                if groups[project.id] == nil {
                    groups[project.id] = []
                    order.append(project.id)
                }
                groups[project.id]?.append(m)
            }
        }

        let fleetProjects: [FleetProject] = order.map { id in
            // Stable host order within a project.
            let materializations = (groups[id] ?? []).sorted { $0.serverId < $1.serverId }
            let canonicalName = Self.canonicalName(materializations)
            return FleetProject(
                id: id,
                name: canonicalName,
                materializations: materializations,
                drift: FleetDrift.compute(materializations)
            )
        }

        // Stable, human-friendly portfolio order: name (case-insensitive),
        // then id to break ties deterministically.
        let sorted = fleetProjects.sorted { a, b in
            let an = a.name.lowercased(), bn = b.name.lowercased()
            if an != bn { return an < bn }
            return a.id.uuidString < b.id.uuidString
        }
        return ProjectPortfolio(projects: sorted)
    }

    /// Canonical display name = the name on the most-recently-updated
    /// materialization (ties broken by serverId for determinism).
    private static func canonicalName(_ materializations: [FleetMaterialization]) -> String {
        let best = materializations.max { a, b in
            if a.project.updatedAt != b.project.updatedAt {
                return a.project.updatedAt < b.project.updatedAt
            }
            return a.serverId < b.serverId
        }
        return best?.project.name ?? ""
    }
}
