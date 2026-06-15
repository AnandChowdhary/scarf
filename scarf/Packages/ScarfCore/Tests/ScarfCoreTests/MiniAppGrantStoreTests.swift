import Testing
import Foundation
@testable import ScarfCore

/// Coverage for the per-machine mini-app permission grant store. Runs
/// against a fresh temp Hermes home so it never touches the real
/// `~/.hermes/scarf/miniapp_grants.json`.
@Suite struct MiniAppGrantStoreTests {

    static func withTempHome(_ body: (ServerContext) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarf-grants-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try body(ServerContext.local(home: home))
    }

    @Test func emptyWhenNoDecision() throws {
        try Self.withTempHome { ctx in
            let store = MiniAppGrantStore(context: ctx)
            #expect(store.grantedPermissions(projectId: "p", miniAppId: "a").isEmpty)
            #expect(store.hasDecision(projectId: "p", miniAppId: "a") == false)
        }
    }

    @Test func setThenReadRoundTrips() throws {
        try Self.withTempHome { ctx in
            let store = MiniAppGrantStore(context: ctx)
            try store.setGrant(projectId: "p", miniAppId: "a", permissions: [.store, .prompt, .query("kanban.tasks")])
            let granted = store.grantedPermissions(projectId: "p", miniAppId: "a")
            #expect(granted == [.store, .prompt, .query("kanban.tasks")])
            #expect(store.hasDecision(projectId: "p", miniAppId: "a"))
        }
    }

    @Test func upsertReplacesPriorDecision() throws {
        try Self.withTempHome { ctx in
            let store = MiniAppGrantStore(context: ctx)
            try store.setGrant(projectId: "p", miniAppId: "a", permissions: [.store, .prompt])
            try store.setGrant(projectId: "p", miniAppId: "a", permissions: [.store])
            #expect(store.grantedPermissions(projectId: "p", miniAppId: "a") == [.store])
            #expect(store.allGrants().filter { $0.miniAppId == "a" }.count == 1)
        }
    }

    @Test func emptyApprovalIsADistinctDecision() throws {
        try Self.withTempHome { ctx in
            let store = MiniAppGrantStore(context: ctx)
            try store.setGrant(projectId: "p", miniAppId: "a", permissions: [])
            #expect(store.grantedPermissions(projectId: "p", miniAppId: "a").isEmpty)
            #expect(store.hasDecision(projectId: "p", miniAppId: "a"))  // decided "nothing", not "never"
        }
    }

    @Test func revokeForgetsDecision() throws {
        try Self.withTempHome { ctx in
            let store = MiniAppGrantStore(context: ctx)
            try store.setGrant(projectId: "p", miniAppId: "a", permissions: [.store])
            try store.revoke(projectId: "p", miniAppId: "a")
            #expect(store.hasDecision(projectId: "p", miniAppId: "a") == false)
        }
    }

    @Test func grantsAreScopedByProjectAndMiniApp() throws {
        try Self.withTempHome { ctx in
            let store = MiniAppGrantStore(context: ctx)
            try store.setGrant(projectId: "p1", miniAppId: "a", permissions: [.store])
            try store.setGrant(projectId: "p2", miniAppId: "a", permissions: [.prompt])
            #expect(store.grantedPermissions(projectId: "p1", miniAppId: "a") == [.store])
            #expect(store.grantedPermissions(projectId: "p2", miniAppId: "a") == [.prompt])
            #expect(store.grantedPermissions(projectId: "p1", miniAppId: "b").isEmpty)
        }
    }
}
