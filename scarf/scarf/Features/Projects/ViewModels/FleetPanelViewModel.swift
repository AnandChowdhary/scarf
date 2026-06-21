import Foundation
import ScarfCore
import os

/// Backs the cockpit's **Fleet** panel — the per-project slice of the
/// fleet/portfolio dimension (Phase-1 item #4). Given the project the
/// cockpit is showing, it gathers the same stable id across every
/// registered server and exposes that one `FleetProject`: where the
/// project is materialized, and the per-host config drift between hosts.
///
/// The gather (`FleetService.portfolio`) walks each server's registry +
/// records — local disk and, for remote servers, SFTP — so it runs in one
/// off-main `Task.detached` with a loading flag, mirroring
/// `ProjectCockpitViewModel`'s load shape. NON-FATAL: an unreachable
/// remote contributes nothing rather than failing the whole view.
@Observable
@MainActor
final class FleetPanelViewModel {
    private let logger = Logger(subsystem: "com.scarf", category: "FleetPanelViewModel")

    /// Stable id of the project the cockpit is showing — the grouping key.
    let projectID: UUID
    /// `ServerContext.id.uuidString` of the host the cockpit is bound to.
    /// Marks the "source" materialization for apply-to-fleet + the
    /// "this host" badge.
    let currentServerId: String
    /// Every server to gather across (`ServerRegistry.allContexts`).
    let contexts: [ServerContext]

    /// The resolved fleet entry for this id, or `nil` while loading / when
    /// the id isn't live on any registered host.
    var fleetProject: FleetProject?
    var isLoading = false

    @ObservationIgnored private var hasLoaded = false

    init(projectID: UUID, currentServerId: String, contexts: [ServerContext]) {
        self.projectID = projectID
        self.currentServerId = currentServerId
        self.contexts = contexts
    }

    /// The current host's materialization — the "source" config that
    /// apply-to-fleet pushes onto other hosts.
    var sourceMaterialization: FleetMaterialization? {
        fleetProject?.materialization(serverId: currentServerId)
    }

    /// Materializations on hosts other than the current one — the
    /// candidate apply targets.
    var otherMaterializations: [FleetMaterialization] {
        (fleetProject?.materializations ?? []).filter { $0.serverId != currentServerId }
    }

    func load(force: Bool = false) async {
        if hasLoaded && !force { return }
        hasLoaded = true
        isLoading = true

        let contexts = self.contexts
        let id = self.projectID

        let result = await Task.detached(priority: .userInitiated) { () -> FleetProject? in
            FleetService(contexts: contexts).fleetProject(id: id)
        }.value

        fleetProject = result
        isLoading = false
    }
}
