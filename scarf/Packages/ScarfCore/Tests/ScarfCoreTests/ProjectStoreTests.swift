import Testing
import Foundation
@testable import ScarfCore

/// Disk-integration coverage for `ProjectStore`: canonical record
/// round-trip, facet derivation from existing on-disk state, registry
/// UUID back-fill, and additive/idempotent migration. Each test runs
/// against a fresh per-test temp Hermes home injected via
/// `ServerContext.local(home:)`, so reads/writes never touch the
/// developer's real `~/.hermes`.
@Suite struct ProjectStoreTests {

    /// Run `body` against a `.local` context rooted at a unique temp
    /// home, with a `projects/` subdir for project trees. Cleaned up
    /// afterwards.
    static func withTempHome(_ body: (ServerContext, _ projectsRoot: String) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarf-projectstore-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let projectsRoot = home.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try body(ServerContext.local(home: home), projectsRoot.path)
    }

    /// Create `<projectsRoot>/<slug>/.scarf/` and return the project dir.
    static func makeProjectDir(_ projectsRoot: String, slug: String) throws -> String {
        let dir = projectsRoot + "/" + slug
        try FileManager.default.createDirectory(atPath: dir + "/.scarf", withIntermediateDirectories: true)
        return dir
    }

    static func write(_ contents: String, to path: String) throws {
        try contents.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Record round-trip

    @Test func saveWritesRecordAndIndexesRegistry() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dir = try Self.makeProjectDir(projectsRoot, slug: "alpha")
            let store = ProjectStore(context: ctx)
            let project = ScarfProject(name: "Alpha", rootPath: dir, board: "scarf:alpha")
            try store.save(project)

            // Canonical record landed.
            let loaded = store.load(projectPath: dir)
            #expect(loaded?.id == project.id)
            #expect(loaded?.name == "Alpha")
            #expect(loaded?.board == "scarf:alpha")

            // Registry index carries the UUID.
            let registry = ProjectDashboardService(context: ctx).loadRegistry()
            let entry = registry.projects.first { $0.path == dir }
            #expect(entry != nil)
            #expect(entry?.uuid == project.id)
        }
    }

    @Test func loadReturnsNilWhenRecordMissing() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dir = try Self.makeProjectDir(projectsRoot, slug: "ghost")
            #expect(ProjectStore(context: ctx).load(projectPath: dir) == nil)
        }
    }

    // MARK: - Derive from existing facets

    @Test func deriveReadsManifestConfigCronLock() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dir = try Self.makeProjectDir(projectsRoot, slug: "example")
            let scarf = dir + "/.scarf"

            // manifest.json → modelPresetID + kanbanTenant + template id/version
            try Self.write("""
            {
              "schemaVersion": 3,
              "id": "author/example",
              "name": "Example",
              "version": "1.2.3",
              "description": "x",
              "contents": { "dashboard": true, "agentsMd": true },
              "kanbanTenant": "scarf:example",
              "modelPresetID": "11111111-2222-3333-4444-555555555555"
            }
            """, to: scarf + "/manifest.json")

            // config.json → one secret (keychain ref) + one plain value
            try Self.write("""
            {
              "schemaVersion": 2,
              "templateId": "author/example",
              "values": {
                "site_url": "https://example.com",
                "api_token": "keychain://com.scarf.template.author-example/api_token:abc123"
              },
              "updatedAt": "2026-04-24T00:00:00Z"
            }
            """, to: scarf + "/config.json")

            // template.lock.json → templateLockRef + memory block id
            try Self.write("""
            {
              "template_id": "author/example",
              "template_version": "1.2.3",
              "template_name": "Example",
              "installed_at": "2026-04-24T00:00:00Z",
              "project_files": [],
              "skills_files": [],
              "cron_job_names": ["[tmpl:author/example] nightly"],
              "memory_block_id": "scarf-template:author/example"
            }
            """, to: scarf + "/template.lock.json")

            // ~/.hermes/cron/jobs.json → one [tmpl:] job for this template
            try FileManager.default.createDirectory(atPath: ctx.paths.home + "/cron", withIntermediateDirectories: true)
            try Self.write("""
            {
              "jobs": [
                {
                  "id": "job-nightly",
                  "name": "[tmpl:author/example] nightly",
                  "prompt": "do it",
                  "schedule": { "kind": "cron", "expression": "0 0 * * *" },
                  "enabled": true,
                  "state": "scheduled"
                },
                {
                  "id": "job-unrelated",
                  "name": "some other job",
                  "prompt": "p",
                  "schedule": { "kind": "cron", "expression": "0 1 * * *" },
                  "enabled": true,
                  "state": "scheduled"
                }
              ]
            }
            """, to: ctx.paths.cronJobsJSON)

            let entry = ProjectEntry(name: "Example", path: dir)
            let derived = ProjectStore(context: ctx).derive(from: entry)

            #expect(derived.name == "Example")
            #expect(derived.rootPath == dir)
            #expect(derived.modelPresetId == "11111111-2222-3333-4444-555555555555")
            #expect(derived.board == "scarf:example")
            #expect(derived.templateLockRef == scarf + "/template.lock.json")
            #expect(derived.memoryNamespace == "scarf-template:author/example")
            // Only the matching [tmpl:] job is attributed.
            #expect(derived.cronJobIds == ["job-nightly"])
            // SECRET-SAFE: only the secret KEY name, never the value.
            #expect(derived.secretsScope == ["api_token"])
            #expect(!derived.secretsScope.contains("site_url"))
            // One host binding, this server.
            #expect(derived.hostBindings.count == 1)
            #expect(derived.hostBindings.first?.serverId == ctx.id.uuidString)
        }
    }

    @Test func deriveBareProjectIsEmpty() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dir = try Self.makeProjectDir(projectsRoot, slug: "bare")
            let derived = ProjectStore(context: ctx).derive(from: ProjectEntry(name: "Bare", path: dir))
            #expect(derived.modelPresetId == nil)
            #expect(derived.board == nil)
            #expect(derived.templateLockRef == nil)
            #expect(derived.cronJobIds.isEmpty)
            #expect(derived.secretsScope.isEmpty)
            #expect(derived.memoryNamespace == nil)
        }
    }

    @Test func deriveReusesEntryUUID() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dir = try Self.makeProjectDir(projectsRoot, slug: "stable")
            let id = UUID()
            let derived = ProjectStore(context: ctx)
                .derive(from: ProjectEntry(name: "Stable", path: dir, uuid: id))
            #expect(derived.id == id)
        }
    }

    // MARK: - Migration

    @Test func migrationIsAdditiveAndIdempotent() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dirA = try Self.makeProjectDir(projectsRoot, slug: "a")
            let dirB = try Self.makeProjectDir(projectsRoot, slug: "b")
            let dashboard = ProjectDashboardService(context: ctx)
            try dashboard.saveRegistry(ProjectRegistry(projects: [
                ProjectEntry(name: "A", path: dirA),
                ProjectEntry(name: "B", path: dirB),
            ]))

            let store = ProjectStore(context: ctx)
            // First run migrates both rows.
            #expect(store.derive() == 2)
            #expect(store.load(projectPath: dirA) != nil)
            #expect(store.load(projectPath: dirB) != nil)
            let after = dashboard.loadRegistry()
            #expect(after.projects.allSatisfy { $0.uuid != nil })

            // Second run is a no-op — records + UUIDs already present.
            #expect(store.derive() == 0)
        }
    }

    @Test func migrationBackfillsUUIDWithoutRewritingExistingRecord() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dir = try Self.makeProjectDir(projectsRoot, slug: "rec")
            let store = ProjectStore(context: ctx)
            // Pre-existing canonical record, but the registry row lacks
            // the UUID (simulates a record written by a peer + a
            // legacy registry).
            let project = ScarfProject(name: "Rec", rootPath: dir)
            try store.writeRecordForTest(project)
            try ProjectDashboardService(context: ctx).saveRegistry(
                ProjectRegistry(projects: [ProjectEntry(name: "Rec", path: dir)])
            )

            #expect(store.derive() == 1)
            let entry = ProjectDashboardService(context: ctx).loadRegistry().projects.first { $0.path == dir }
            // Back-filled to the record's id (not a freshly minted one).
            #expect(entry?.uuid == project.id)
        }
    }

    // MARK: - List

    @Test func listPrefersCanonicalRecordThenDerives() throws {
        try Self.withTempHome { ctx, projectsRoot in
            let dirSaved = try Self.makeProjectDir(projectsRoot, slug: "saved")
            let dirBare = try Self.makeProjectDir(projectsRoot, slug: "barelisted")
            let store = ProjectStore(context: ctx)
            let saved = ScarfProject(name: "Saved", rootPath: dirSaved, board: "scarf:saved")
            try store.save(saved)
            try ProjectDashboardService(context: ctx).saveRegistry(ProjectRegistry(projects: [
                ProjectEntry(name: "Saved", path: dirSaved, uuid: saved.id),
                ProjectEntry(name: "Bare", path: dirBare),
            ]))

            let listed = store.list()
            #expect(listed.count == 2)
            let savedOut = listed.first { $0.rootPath == dirSaved }
            #expect(savedOut?.id == saved.id)
            #expect(savedOut?.board == "scarf:saved")
            // Bare one is derived (no record) — still appears.
            #expect(listed.contains { $0.rootPath == dirBare })
        }
    }
}

// Test-only seam: write the canonical record WITHOUT touching the
// registry, to set up the "record exists, registry stale" migration case.
extension ProjectStore {
    nonisolated func writeRecordForTest(_ project: ScarfProject) throws {
        let scarfDir = project.rootPath + "/.scarf"
        try transport.createDirectory(scarfDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try transport.writeFile(
            ProjectStore.recordPath(forProjectPath: project.rootPath),
            data: encoder.encode(project)
        )
    }
}
