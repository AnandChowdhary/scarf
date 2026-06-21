import Foundation
#if canImport(os)
import os
#endif

/// The fleet/portfolio reader — gathers `ScarfProject`s across every
/// server the user has registered and groups them by stable id into a
/// `ProjectPortfolio` (Phase-1 item #4, the "Fleet dimension").
///
/// **Read-only.** `portfolio()` runs `ProjectStore.list()` per context
/// (which derives missing records on the fly but does NOT persist), then
/// hands the per-host lists to the pure `ProjectPortfolio.build(from:)`
/// grouper. Nothing is written; the disk/SFTP reads mean callers must run
/// it off the main actor.
///
/// **Why contexts are injected, not discovered.** The list of servers
/// lives in the Mac app target's `ServerRegistry` (`servers.json`), which
/// ScarfCore can't see. The caller passes `registry.allContexts` in; this
/// keeps `FleetService` a pure, transport-driven ScarfCore service that
/// iterates whatever hosts it's given — and trivially unit-testable
/// against a couple of temp-home `.local` contexts.
public struct FleetService: Sendable {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.scarf", category: "FleetService")
    #endif

    /// The servers to gather across. Order is preserved into per-host
    /// gather order; the portfolio itself re-sorts for display.
    public let contexts: [ServerContext]

    public nonisolated init(contexts: [ServerContext]) {
        self.contexts = contexts
    }

    // MARK: - Gather

    /// Gather every host's projects and group them into the portfolio.
    /// Disk/SFTP I/O — call off-main. A host whose registry can't be read
    /// contributes an empty list rather than failing the whole gather
    /// (NON-FATAL: one unreachable remote never blanks the fleet view).
    public nonisolated func portfolio() -> ProjectPortfolio {
        let hosts: [ProjectPortfolio.HostProjects] = contexts.map { ctx in
            ProjectPortfolio.HostProjects(
                serverId: ctx.id.uuidString,
                serverDisplayName: ctx.displayName,
                projects: stablyIdentifiedProjects(on: ctx)
            )
        }
        return ProjectPortfolio.build(from: hosts)
    }

    /// Every project on `ctx` that carries a **stable** id — the canonical
    /// `.scarf/project.json` record when present, else a derive from a
    /// registry row that already holds a `uuid`.
    ///
    /// **Why not `ProjectStore.list()`.** `list()` falls back to
    /// `derive(from:)`, which mints a *fresh random* `UUID` for a registry
    /// row that has neither a record nor a uuid (the transient-id trap M1
    /// warned about). A per-gather random id can never group across hosts:
    /// it would surface the project as a flickering single-host phantom
    /// that changes identity on every reload. So the fleet gather is
    /// stricter than `list()` — it **skips** rows without a stable id.
    /// Those rows acquire one through normal migration (opening the
    /// project / cockpit, or the per-host eager `derive()` pass) and then
    /// appear in the fleet. Read-only — never persists.
    private nonisolated func stablyIdentifiedProjects(on ctx: ServerContext) -> [ScarfProject] {
        let store = ProjectStore(context: ctx)
        let registry = ProjectDashboardService(context: ctx).loadRegistry()
        return registry.projects.compactMap { entry in
            if let record = store.load(projectPath: entry.path) { return record }
            if entry.uuid != nil { return store.derive(from: entry) }
            return nil
        }
    }

    /// Scoped lookup for the per-project cockpit Fleet panel: the fleet
    /// entry for one stable id across the registered servers, or `nil`
    /// when the id isn't live anywhere (shouldn't happen for a project
    /// the user is actively viewing, but the gather is best-effort).
    /// Disk/SFTP I/O — call off-main.
    public nonisolated func fleetProject(id: UUID) -> FleetProject? {
        portfolio().project(id: id)
    }
}
