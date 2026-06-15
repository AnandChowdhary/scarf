import Foundation
import WebKit
import ScarfCore
import os

/// Serves a single mini-app's assets over `scarf-miniapp://`, scoped to
/// that mini-app's directory. The path-containment + MIME + CSP logic
/// lives in `ScarfCore.MiniAppAssetResolver` (pure + unit-tested); this is
/// the thin WebKit shell that reads the resolved file and hands it back.
///
/// **Read-only + directory-scoped.** Every request resolves through the
/// resolver, which rejects any path that escapes `baseDirectory`. The
/// response carries a strict CSP (no network) and `nosniff`. There is no
/// directory listing and no write path.
///
/// **Synchronous by design.** Assets are small local files served inline
/// within `start(_:)` on the main thread, so the task can't be `stop`-ed
/// mid-serve — that avoids the "message a stopped `WKURLSchemeTask`"
/// crash class that only bites asynchronous handlers.
final class MiniAppSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let logger = Logger(subsystem: "com.scarf", category: "MiniAppSchemeHandler")

    private let baseDirectory: String

    init(baseDirectory: String) {
        self.baseDirectory = baseDirectory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        guard let filePath = MiniAppAssetResolver.resolvedPath(
            requestPath: url.path,
            baseDirectory: baseDirectory
        ) else {
            Self.logger.warning("blocked out-of-bounds mini-app request: \(url.path, privacy: .public)")
            respond(urlSchemeTask, url: url, status: 404, mime: "text/plain; charset=utf-8", body: Data("Not found".utf8))
            return
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: filePath, isDirectory: &isDir),
              !isDir.boolValue,
              let data = fm.contents(atPath: filePath) else {
            respond(urlSchemeTask, url: url, status: 404, mime: "text/plain; charset=utf-8", body: Data("Not found".utf8))
            return
        }

        respond(
            urlSchemeTask,
            url: url,
            status: 200,
            mime: MiniAppAssetResolver.mimeType(forPath: filePath),
            body: data
        )
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op: serving completes synchronously in `start`, so there is
        // never an in-flight task to cancel.
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, body: Data) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(body.count),
            "Content-Security-Policy": MiniAppAssetResolver.contentSecurityPolicy,
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "no-store",
        ]
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
