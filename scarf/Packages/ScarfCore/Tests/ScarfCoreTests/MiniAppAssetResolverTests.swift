import Testing
import Foundation
@testable import ScarfCore

/// Security-critical coverage for the `scarf-miniapp://` path resolver:
/// legitimate assets resolve inside the mini-app dir; every traversal /
/// escape attempt is rejected.
@Suite struct MiniAppAssetResolverTests {

    static let base = "/tmp/proj/.scarf/miniapps/app"

    @Test func resolvesAssetsInsideBase() {
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "/index.html", baseDirectory: Self.base)
            == Self.base + "/index.html")
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "assets/app.js", baseDirectory: Self.base)
            == Self.base + "/assets/app.js")
        // A leading-slash "absolute" path is treated as relative to base
        // (so it stays contained — names a would-be "etc" subdir, not /etc).
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "/etc/passwd", baseDirectory: Self.base)
            == Self.base + "/etc/passwd")
    }

    @Test func rejectsTraversalEscapes() {
        let escapes = [
            "../secret",
            "../../../../etc/passwd",
            "sub/../../../escape",
            "..",
            "../",
        ]
        for path in escapes {
            #expect(
                MiniAppAssetResolver.resolvedPath(requestPath: path, baseDirectory: Self.base) == nil,
                "expected escape \"\(path)\" to be rejected"
            )
        }
    }

    @Test func rejectsEmptyAndDirectoryItself() {
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "", baseDirectory: Self.base) == nil)
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "/", baseDirectory: Self.base) == nil)
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: ".", baseDirectory: Self.base) == nil)
    }

    @Test func rejectsControlCharacters() {
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "a\u{0}b", baseDirectory: Self.base) == nil)
        #expect(MiniAppAssetResolver.resolvedPath(requestPath: "a\nb", baseDirectory: Self.base) == nil)
    }

    @Test func mimeTypesByExtension() {
        #expect(MiniAppAssetResolver.mimeType(forPath: "x/index.html").hasPrefix("text/html"))
        #expect(MiniAppAssetResolver.mimeType(forPath: "app.js").hasPrefix("text/javascript"))
        #expect(MiniAppAssetResolver.mimeType(forPath: "a.css").hasPrefix("text/css"))
        #expect(MiniAppAssetResolver.mimeType(forPath: "d.json").hasPrefix("application/json"))
        #expect(MiniAppAssetResolver.mimeType(forPath: "i.png") == "image/png")
        #expect(MiniAppAssetResolver.mimeType(forPath: "v.svg") == "image/svg+xml")
        #expect(MiniAppAssetResolver.mimeType(forPath: "x.unknownext") == "application/octet-stream")
    }

    @Test func entryURLNormalizes() {
        #expect(MiniAppAssetResolver.entryURLString(entry: "index.html") == "scarf-miniapp://app/index.html")
        #expect(MiniAppAssetResolver.entryURLString(entry: "/app.html") == "scarf-miniapp://app/app.html")
        #expect(MiniAppAssetResolver.entryURLString(entry: "") == "scarf-miniapp://app/index.html")
    }

    @Test func cspBlocksNetwork() {
        // The load-bearing line: no outbound connections in v1.
        #expect(MiniAppAssetResolver.contentSecurityPolicy.contains("connect-src 'none'"))
        #expect(MiniAppAssetResolver.contentSecurityPolicy.contains("default-src 'none'"))
    }

    /// The HIGH-severity fix: a symlink planted inside the mini-app dir must
    /// not be readable through to a target outside the dir.
    @Test func containedFilePathRejectsEscapingSymlink() throws {
        let fm = FileManager.default
        let base = NSTemporaryDirectory() + "scarf-miniapp-base-" + UUID().uuidString
        let outside = NSTemporaryDirectory() + "scarf-miniapp-outside-" + UUID().uuidString
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: base); try? fm.removeItem(atPath: outside) }

        try Data("<html>".utf8).write(to: URL(fileURLWithPath: base + "/index.html"))
        try Data("TOPSECRET".utf8).write(to: URL(fileURLWithPath: outside + "/secret.txt"))
        try fm.createSymbolicLink(atPath: base + "/leak", withDestinationPath: outside + "/secret.txt")
        try fm.createDirectory(atPath: base + "/sub", withIntermediateDirectories: true)

        // Real in-dir file → allowed.
        #expect(MiniAppAssetResolver.containedFilePath(requestPath: "/index.html", baseDirectory: base) != nil)
        // Symlink escaping the dir → refused (the bypass that was the bug).
        #expect(MiniAppAssetResolver.containedFilePath(requestPath: "/leak", baseDirectory: base) == nil)
        // A directory is not a servable file.
        #expect(MiniAppAssetResolver.containedFilePath(requestPath: "/sub", baseDirectory: base) == nil)
        // Missing file → nil.
        #expect(MiniAppAssetResolver.containedFilePath(requestPath: "/nope.js", baseDirectory: base) == nil)
        // Lexical escape still rejected before any FS touch.
        #expect(MiniAppAssetResolver.containedFilePath(requestPath: "../secret.txt", baseDirectory: base) == nil)
    }
}
