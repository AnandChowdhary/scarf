import SwiftUI
import WebKit
import ScarfCore
import os

/// Renders one mini-app inside Scarf — a `WKWebView` wired to the
/// directory-scoped `scarf-miniapp://` scheme handler. This is the host
/// surface from the Mini-App Bridge Contract; the `window.scarf` bridge is
/// layered on in a later increment, so v1 renders a sandboxed *static*
/// surface (strict CSP, no network, no tool access).
///
/// **Sandboxing in this layer:**
/// - Non-persistent data store (no cookies/localStorage leak across apps).
/// - Assets only via the scheme handler scoped to the mini-app dir.
/// - Navigation locked to `scarf-miniapp://` — any attempt to navigate to
///   `https://`/`file://`/external is cancelled (defense in depth behind CSP).
struct MiniAppHostView: NSViewRepresentable {
    let projectPath: String
    let manifest: MiniAppManifest

    func makeNSView(context: Context) -> WKWebView {
        let baseDir = MiniAppService.miniAppDir(forProjectPath: projectPath, id: manifest.id)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(
            MiniAppSchemeHandler(baseDirectory: baseDir),
            forURLScheme: MiniAppAssetResolver.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Mini-apps are self-contained; no back/forward gestures.
        webView.allowsBackForwardNavigationGestures = false
        load(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload only when the bound mini-app actually changes.
        guard context.coordinator.loadedAppID != manifest.id else { return }
        context.coordinator.loadedAppID = manifest.id
        load(into: webView)
    }

    private func load(into webView: WKWebView) {
        guard let url = URL(string: MiniAppAssetResolver.entryURLString(entry: manifest.entry)) else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator(appID: manifest.id) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "com.scarf", category: "MiniAppHostView")
        var loadedAppID: String

        init(appID: String) { self.loadedAppID = appID }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Only our own scheme may load. Everything else — external
            // links, file://, http(s):// — is refused. (A future increment
            // can route user-intended external links out via NSWorkspace
            // behind a confirmation; v1 simply blocks.)
            if navigationAction.request.url?.scheme == MiniAppAssetResolver.scheme {
                decisionHandler(.allow)
            } else {
                logger.warning("blocked mini-app navigation to non-scheme URL")
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.warning("mini-app navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.warning("mini-app failed to load: \(error.localizedDescription, privacy: .public)")
        }
    }
}
