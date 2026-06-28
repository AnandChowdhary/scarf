import Testing
import Foundation
@testable import ScarfCore

/// Coverage for the session→project attribution sidecar and its
/// `resolveProjectPath` recovery seam — the source of truth that lets a
/// RESUMED / reconnected / auto-started project chat re-derive its
/// project dir (cwd) when the UI doesn't pass one in (t-24594c4a).
/// Runs against a fresh temp Hermes home so it never touches the real
/// `~/.hermes/scarf/session_project_map.json`.
@Suite struct SessionAttributionServiceTests {

    static func withTempHome(_ body: (ServerContext) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarf-attribution-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try body(ServerContext.local(home: home))
    }

    // MARK: - attribute → projectPath round-trip (the recovery source)

    @Test func attributeThenLookupRoundTrips() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            #expect(svc.projectPath(for: "s1") == nil)
            svc.attribute(sessionID: "s1", toProjectPath: "/Projects/news")
            #expect(svc.projectPath(for: "s1") == "/Projects/news")
        }
    }

    @Test func attributeIsIdempotentAndLastWriteWins() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            svc.attribute(sessionID: "s1", toProjectPath: "/Projects/news")
            svc.attribute(sessionID: "s1", toProjectPath: "/Projects/news")  // idempotent
            #expect(svc.projectPath(for: "s1") == "/Projects/news")
            svc.attribute(sessionID: "s1", toProjectPath: "/Projects/stocker")  // re-point
            #expect(svc.projectPath(for: "s1") == "/Projects/stocker")
        }
    }

    @Test func reverseLookupAndForget() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            svc.attribute(sessionID: "a", toProjectPath: "/Projects/news")
            svc.attribute(sessionID: "b", toProjectPath: "/Projects/news")
            svc.attribute(sessionID: "c", toProjectPath: "/Projects/stocker")
            #expect(svc.sessionIDs(forProject: "/Projects/news") == ["a", "b"])
            svc.forget(sessionID: "a")
            #expect(svc.sessionIDs(forProject: "/Projects/news") == ["b"])
            #expect(svc.projectPath(for: "a") == nil)
        }
    }

    // MARK: - resolveProjectPath (the resume/reconnect/auto-start seam)

    @Test func resolveKnownPathWinsWithoutTouchingSidecar() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            // Even when the session is attributed elsewhere, a caller-known
            // path takes precedence (reconnect/auto-start pass currentProjectPath).
            svc.attribute(sessionID: "s1", toProjectPath: "/Projects/attributed")
            #expect(svc.resolveProjectPath(known: "/Projects/explicit", sessionID: "s1") == "/Projects/explicit")
            // Known path wins even with no session id at all.
            #expect(svc.resolveProjectPath(known: "/Projects/explicit", sessionID: nil) == "/Projects/explicit")
        }
    }

    @Test func resolveFallsBackToAttributionWhenKnownIsNilOrEmpty() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            svc.attribute(sessionID: "s1", toProjectPath: "/Projects/news")
            // nil known → recover via the sidecar (the RESUME path).
            #expect(svc.resolveProjectPath(known: nil, sessionID: "s1") == "/Projects/news")
            // empty / whitespace-only known is treated as "no known path".
            #expect(svc.resolveProjectPath(known: "", sessionID: "s1") == "/Projects/news")
            #expect(svc.resolveProjectPath(known: "   ", sessionID: "s1") == "/Projects/news")
        }
    }

    @Test func resolveReturnsRealKnownPathVerbatim() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            // A real path is returned unchanged — including a legitimate
            // trailing-space directory name (only the emptiness test trims).
            #expect(svc.resolveProjectPath(known: "/Projects/has space ", sessionID: nil) == "/Projects/has space ")
        }
    }

    @Test func resolveReturnsNilForUnattributedOrMissingSession() throws {
        try Self.withTempHome { ctx in
            let svc = SessionAttributionService(context: ctx)
            // Unattributed session (e.g. a global/CLI chat) → nil → caller
            // uses home cwd, preserving non-project behavior.
            #expect(svc.resolveProjectPath(known: nil, sessionID: "unknown") == nil)
            // No known path and no session to look up → nil.
            #expect(svc.resolveProjectPath(known: nil, sessionID: nil) == nil)
            #expect(svc.resolveProjectPath(known: "", sessionID: nil) == nil)
        }
    }
}
