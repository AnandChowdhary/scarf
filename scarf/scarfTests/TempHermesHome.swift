import Foundation
import ScarfCore

/// A disposable Hermes home under the system temp dir, paired with a
/// `ServerContext.local(home:)` that steers every ScarfCore service's file
/// I/O into it.
///
/// Replaces the old `SCARF_HERMES_HOME` env-redirect + global
/// `TestRegistryLock` pattern that app-target suites used to isolate their
/// `~/.hermes` writes. Because the home is per-instance and `.local(home:)`
/// resolves `paths.*` from `localHomeOverride` — bypassing
/// `HermesProfileResolver`/`HermesPathSet.defaultLocalHome` and the global
/// env entirely — suites that adopt this share NO mutable process state.
/// They need no cross-suite serialization, which removes the
/// `@MainActor`-blocking deadlock that the shared `NSLock` produced (see
/// the `testregistrylock-…-deadlocks-across-parallel-suites` memory note
/// and `scarfcore-tests-inject-a-temp-hermes-home-via-servercontext-local-home`).
///
/// Usage:
/// ```swift
/// let home = try TempHermesHome()
/// defer { home.cleanup() }
/// let vm = ProjectsViewModel(context: home.context)
/// ```
struct TempHermesHome {
    /// Root of the throwaway home (e.g. `/var/folders/…/scarf-test-home-<uuid>`).
    let url: URL

    /// A `.local`-kind context whose `paths.*` resolve under `url` instead
    /// of the developer's real `~/.hermes`. Keeps `id == ServerContext.local.id`
    /// so `vm.context.id == ServerContext.local.id` assertions still hold —
    /// only `paths.home` differs. Recomputed cheaply on each access.
    var context: ServerContext { .local(home: url) }

    /// The home directory as a plain path string, for building fixture
    /// paths by hand (e.g. `home.path + "/scarf/projects.json"`).
    var path: String { url.path }

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scarf-test-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Recursively remove the temp home. Safe in a `defer`; ignores the
    /// "already gone" case.
    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}
