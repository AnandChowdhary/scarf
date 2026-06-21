import Foundation
import ScarfCore

/// Drives the `FleetApplySheet` — the user's pick of which config fields
/// to push and which hosts to push them to, the live plan preview, and
/// the off-main execution.
///
/// The plan is **recomputed purely** from the current selections
/// (`FleetApplyPlan.make`) so the preview always matches what Apply will
/// do. Execution runs `FleetApplyExecutor` in a detached task and lands
/// per-target results.
@Observable
@MainActor
final class FleetApplyViewModel {

    /// The current host's materialization — the config being pushed.
    let source: FleetMaterialization
    /// Candidate target hosts (every other host the project is on).
    let candidates: [FleetMaterialization]
    /// All registered servers, for the executor's serverId → context map.
    let contexts: [ServerContext]
    /// Fields the source actually carries — the only ones offered.
    let applicableFields: Set<FleetApplyField>

    var selectedTargetIds: Set<String>
    var selectedFields: Set<FleetApplyField>
    var phase: Phase = .configuring

    enum Phase {
        case configuring
        case applying
        case done([FleetApplyExecutor.TargetResult])
    }

    /// Whether an apply is in flight — drives the sheet's disabled state
    /// without an `Equatable` conformance on `Phase` (whose `.done`
    /// associated value isn't meaningfully comparable).
    var isApplying: Bool {
        if case .applying = phase { return true }
        return false
    }

    init(source: FleetMaterialization, candidates: [FleetMaterialization], contexts: [ServerContext]) {
        self.source = source
        self.candidates = candidates
        self.contexts = contexts
        let applicable = FleetApplyPlan.applicableFields(source: source.project)
        self.applicableFields = applicable
        self.selectedFields = applicable                       // default: everything pushable
        self.selectedTargetIds = Set(candidates.map(\.serverId))  // default: every host
    }

    var selectedTargets: [FleetMaterialization] {
        candidates.filter { selectedTargetIds.contains($0.serverId) }
    }

    /// The live plan for the current selections — also the preview source.
    var plan: FleetApplyPlan {
        FleetApplyPlan.make(source: source, targets: selectedTargets, fields: selectedFields)
    }

    /// Apply is enabled only when at least one selected host will actually
    /// change at least one field (a selection that's entirely no-ops is
    /// pointless).
    var canApply: Bool {
        guard !selectedFields.isEmpty, !selectedTargetIds.isEmpty else { return false }
        return !plan.effectiveTargets.isEmpty
    }

    func isFieldSelected(_ field: FleetApplyField) -> Bool { selectedFields.contains(field) }

    func toggleField(_ field: FleetApplyField, _ on: Bool) {
        if on { selectedFields.insert(field) } else { selectedFields.remove(field) }
    }

    func isTargetSelected(_ serverId: String) -> Bool { selectedTargetIds.contains(serverId) }

    func toggleTarget(_ serverId: String, _ on: Bool) {
        if on { selectedTargetIds.insert(serverId) } else { selectedTargetIds.remove(serverId) }
    }

    func apply() async {
        guard canApply else { return }
        phase = .applying
        let plan = self.plan
        let sourceProject = source.project
        let contexts = self.contexts
        let results = await Task.detached(priority: .userInitiated) { () -> [FleetApplyExecutor.TargetResult] in
            FleetApplyExecutor(contexts: contexts).execute(plan, source: sourceProject)
        }.value
        phase = .done(results)
    }
}
