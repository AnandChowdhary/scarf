import Testing
import Foundation
import ScarfCore
@testable import scarf

/// Coverage for the deterministic half of "Upgrade Project"
/// (`ProjectUpgradeService`): it brings a basic/legacy project up to the
/// first-class structure idempotently, reusing the scaffolder's writers,
/// without clobbering user content. Each test runs in its own
/// `TempHermesHome` (per-instance `ServerContext.local(home:)`), so the
/// registry + project files are sandboxed and the suite is parallel-safe.
@Suite struct ProjectUpgradeServiceTests {

    /// Create `<home>/projects/<slug>/.scarf/` and register the project,
    /// returning the registered entry.
    static func makeRegisteredProject(_ home: TempHermesHome, name: String, slug: String) throws -> ProjectEntry {
        let dir = home.path + "/projects/" + slug
        try FileManager.default.createDirectory(atPath: dir + "/.scarf", withIntermediateDirectories: true)
        let entry = ProjectEntry(name: name, path: dir)
        try ProjectDashboardService(context: home.context).saveRegistry(ProjectRegistry(projects: [entry]))
        return entry
    }

    static func write(_ contents: String, to path: String) throws {
        try contents.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Bare project → full structure

    @Test func upgradeBareProjectCreatesAllFacets() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "Basic", slug: "basic")

        let outcome = try ProjectUpgradeService(context: home.context).upgrade(entry, hasKanban: true)

        // Stable identity: project.json written, registry back-filled with the same id.
        let record = try #require(ProjectStore(context: home.context).load(projectPath: entry.path))
        #expect(record.id == outcome.projectID)
        let row = ProjectDashboardService(context: home.context).loadRegistry().projects.first { $0.path == entry.path }
        #expect(row?.uuid == outcome.projectID)

        // AGENTS.md managed block.
        let agents = try String(contentsOfFile: entry.path + "/AGENTS.md", encoding: .utf8)
        #expect(agents.contains(ProjectContextBlock.beginMarker))
        #expect(agents.contains(ProjectContextBlock.endMarker))

        // Board minted (hasKanban) + surfaced in the manifest.
        #expect(outcome.board != nil)
        #expect(KanbanTenantReader(context: home.context).tenant(forProjectPath: entry.path) == outcome.board)

        // Dashboard seeded + provenance stamped.
        #expect(outcome.dashboardSeeded)
        #expect(FileManager.default.fileExists(atPath: entry.path + "/.scarf/dashboard.json"))
        #expect(FileManager.default.fileExists(atPath: entry.path + "/.scarf/upgrade.json"))
        #expect(outcome.wasAlreadyUpgraded == false)
    }

    // MARK: - Idempotency

    @Test func upgradeIsIdempotent() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "Idem", slug: "idem")
        let service = ProjectUpgradeService(context: home.context)

        let first = try service.upgrade(entry, hasKanban: true)
        let second = try service.upgrade(entry, hasKanban: true)

        // Second run is a no-op: same stable id, already-upgraded, dashboard not reseeded.
        #expect(second.projectID == first.projectID)
        #expect(second.wasAlreadyUpgraded)
        #expect(second.dashboardSeeded == false)
        #expect(first.wasAlreadyUpgraded == false)
    }

    @Test func needsUpgradeReflectsProvenance() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "Needs", slug: "needs")
        let service = ProjectUpgradeService(context: home.context)

        #expect(service.needsUpgrade(entry) == true)
        _ = try service.upgrade(entry, hasKanban: true)
        #expect(service.needsUpgrade(entry) == false)
    }

    // MARK: - Never clobber user content (BOUNDED)

    @Test func upgradePreservesExistingDashboard() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "HasDash", slug: "hasdash")
        let custom = #"{"version":1,"title":"My Real Dashboard","sections":[]}"#
        try Self.write(custom, to: entry.path + "/.scarf/dashboard.json")

        let outcome = try ProjectUpgradeService(context: home.context).upgrade(entry, hasKanban: true)

        // Placeholder NOT written; the user's dashboard survives byte-for-byte.
        #expect(outcome.dashboardSeeded == false)
        let onDisk = try String(contentsOfFile: entry.path + "/.scarf/dashboard.json", encoding: .utf8)
        #expect(onDisk == custom)
    }

    @Test func upgradePreservesUserAgentsContent() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "HasAgents", slug: "hasagents")
        try Self.write("# My Project\n\nHand-written user notes the agent must keep.\n",
                       to: entry.path + "/AGENTS.md")

        _ = try ProjectUpgradeService(context: home.context).upgrade(entry, hasKanban: true)

        let agents = try String(contentsOfFile: entry.path + "/AGENTS.md", encoding: .utf8)
        #expect(agents.contains("Hand-written user notes the agent must keep."))  // user text kept
        #expect(agents.contains(ProjectContextBlock.beginMarker))                  // block spliced in
    }

    // MARK: - Stable id preservation

    @Test func upgradePreservesStableId() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "Stable", slug: "stable")
        // Pre-existing first-class record with a known id.
        let knownID = UUID()
        try ProjectStore(context: home.context).save(ScarfProject(id: knownID, name: "Stable", rootPath: entry.path))

        let outcome = try ProjectUpgradeService(context: home.context).upgrade(entry, hasKanban: true)
        #expect(outcome.projectID == knownID)
        #expect(ProjectStore(context: home.context).load(projectPath: entry.path)?.id == knownID)
    }

    // MARK: - Capability gating

    @Test func upgradeSkipsBoardWithoutKanban() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "NoKanban", slug: "nokanban")

        let outcome = try ProjectUpgradeService(context: home.context).upgrade(entry, hasKanban: false)

        // No tenant minted, no manifest kanbanTenant.
        #expect(outcome.board == nil)
        #expect(KanbanTenantReader(context: home.context).tenant(forProjectPath: entry.path) == nil)
        // ...but the rest of the structure still landed.
        #expect(ProjectStore(context: home.context).load(projectPath: entry.path) != nil)
        #expect(outcome.dashboardSeeded)
    }

    // MARK: - Board lands in the canonical record (regression: project.json/manifest sync)

    @Test func upgradeWritesBoardIntoRecord() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "Boarded", slug: "boarded")

        let outcome = try ProjectUpgradeService(context: home.context).upgrade(entry, hasKanban: true)

        // The minted tenant must land in the canonical record (project.json),
        // not only the manifest — otherwise ScarfProject.board stays nil
        // forever and the Fleet drift/apply machinery reads an empty board.
        let record = try #require(ProjectStore(context: home.context).load(projectPath: entry.path))
        #expect(outcome.board != nil)
        #expect(record.board == outcome.board)
        #expect(record.board == KanbanTenantReader(context: home.context).tenant(forProjectPath: entry.path))
    }

    // MARK: - Provenance version-bump

    @Test func needsUpgradeTrueForOlderProvenanceVersion() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }
        let entry = try Self.makeRegisteredProject(home, name: "Old", slug: "old")
        // Provenance stamped at an OLDER upgrade version than the current one.
        try Self.write(#"{"schemaVersion":1,"upgradeVersion":0,"upgradedAt":"2026-01-01T00:00:00Z"}"#,
                       to: entry.path + "/.scarf/upgrade.json")

        let service = ProjectUpgradeService(context: home.context)
        #expect(service.needsUpgrade(entry) == true)   // older version → still needs upgrading
        _ = try service.upgrade(entry, hasKanban: true)
        #expect(service.needsUpgrade(entry) == false)  // re-stamped at current
    }
}
