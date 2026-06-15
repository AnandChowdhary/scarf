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
}
