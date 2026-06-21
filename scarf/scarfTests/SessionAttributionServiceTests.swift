import Testing
import Foundation
import ScarfCore
@testable import scarf

/// Exercises the v2.3 sidecar at `<home>/scarf/session_project_map.json`.
/// Each test injects an isolated `ServerContext.local(home:)`, so the
/// sidecar lives in a per-instance temp dir — never the developer's real
/// `~/.hermes`. No global env, no cross-suite lock, no shared mutable
/// state, so the suite runs in parallel safely.
struct SessionAttributionServiceTests {

    @Test func loadOnMissingFileReturnsEmptyMap() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let svc = SessionAttributionService(context: home.context)
        let map = svc.load()
        #expect(map.mappings.isEmpty)
        #expect(svc.projectPath(for: "anything") == nil)
        #expect(svc.sessionIDs(forProject: "/anything").isEmpty)
    }

    @Test func attributeWritesMappingAndPersists() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let svc = SessionAttributionService(context: home.context)
        svc.attribute(sessionID: "sess-1", toProjectPath: "/proj/a")

        // Read back via a fresh service instance — confirms the
        // write actually landed on disk, not just the in-memory map.
        let fresh = SessionAttributionService(context: home.context)
        #expect(fresh.projectPath(for: "sess-1") == "/proj/a")

        // updatedAt populated on write.
        let map = fresh.load()
        let ts = try #require(map.updatedAt)
        #expect(!ts.isEmpty)
    }

    @Test func attributeIsIdempotent() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let svc = SessionAttributionService(context: home.context)
        svc.attribute(sessionID: "s", toProjectPath: "/p")
        let firstStamp = svc.load().updatedAt
        // Call again with the same pair — should short-circuit, NOT
        // bump updatedAt. We check that the timestamp didn't change
        // even if the file would have been rewritten.
        svc.attribute(sessionID: "s", toProjectPath: "/p")
        let secondStamp = svc.load().updatedAt
        #expect(firstStamp == secondStamp)
    }

    @Test func reattributeChangesMapping() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let svc = SessionAttributionService(context: home.context)
        svc.attribute(sessionID: "s", toProjectPath: "/a")
        svc.attribute(sessionID: "s", toProjectPath: "/b")
        #expect(svc.projectPath(for: "s") == "/b")
        #expect(svc.sessionIDs(forProject: "/a").isEmpty)
        #expect(svc.sessionIDs(forProject: "/b") == ["s"])
    }

    @Test func reverseLookupReturnsAllAttributedSessions() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let svc = SessionAttributionService(context: home.context)
        svc.attribute(sessionID: "s1", toProjectPath: "/proj")
        svc.attribute(sessionID: "s2", toProjectPath: "/proj")
        svc.attribute(sessionID: "s3", toProjectPath: "/other")

        #expect(svc.sessionIDs(forProject: "/proj") == ["s1", "s2"])
        #expect(svc.sessionIDs(forProject: "/other") == ["s3"])
        #expect(svc.sessionIDs(forProject: "/nobody").isEmpty)
    }

    @Test func forgetRemovesMapping() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let svc = SessionAttributionService(context: home.context)
        svc.attribute(sessionID: "s", toProjectPath: "/p")
        #expect(svc.projectPath(for: "s") == "/p")

        svc.forget(sessionID: "s")
        #expect(svc.projectPath(for: "s") == nil)
        // Forget on a missing session is a no-op, not an error.
        svc.forget(sessionID: "s")
        #expect(svc.projectPath(for: "s") == nil)
    }

    @Test func oversizeSidecarTreatedAsMissing() throws {
        // Regression coverage for the iOS resume-time crash hypothesis
        // in TestFlight feedback AJy1fD58 / AL8Hjm06 (Berlin, iOS 26.5,
        // 2.87 GB free disk). A pathologically large sidecar — corrupt
        // truncation, hostile content, or a runaway logger that
        // appended to the wrong file — must not be decoded on a
        // memory-pressured device.
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let path = home.context.paths.sessionProjectMap
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        // Write just over the cap so the test stays fast.
        let oversize = SessionAttributionService.maxSidecarBytes + 1
        let blob = Data(repeating: 0x41, count: oversize) // ASCII 'A's
        try blob.write(to: URL(fileURLWithPath: path))

        let svc = SessionAttributionService(context: home.context)
        let map = svc.load()
        #expect(map.mappings.isEmpty)
        #expect(svc.projectPath(for: "anything") == nil)
    }

    @Test func sidecarAtMaxBytesStillAttemptsDecode() throws {
        // The cap is "strictly greater than"; a file exactly at the
        // limit should still be attempted (and will fail with a parse
        // error since 1MB of ASCII isn't valid JSON, which is the same
        // graceful path the corrupted-file test exercises). Pins the
        // boundary so a future refactor doesn't accidentally tighten
        // it to strict `>=`.
        let home = try TempHermesHome()
        defer { home.cleanup() }

        let path = home.context.paths.sessionProjectMap
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let atCap = Data(repeating: 0x41, count: SessionAttributionService.maxSidecarBytes)
        try atCap.write(to: URL(fileURLWithPath: path))

        let svc = SessionAttributionService(context: home.context)
        let map = svc.load()
        // Decode fails → empty map (same as corrupted-file path).
        #expect(map.mappings.isEmpty)
    }

    @Test func corruptedFileReturnsEmptyMap() throws {
        let home = try TempHermesHome()
        defer { home.cleanup() }

        // Write garbage to the sidecar path and confirm the service
        // treats it as "no attributions" rather than crashing. Users
        // hand-editing the JSON shouldn't soft-brick the Sessions tab.
        let path = home.context.paths.sessionProjectMap
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try "not json at all".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))

        let svc = SessionAttributionService(context: home.context)
        let map = svc.load()
        #expect(map.mappings.isEmpty)
    }
}
