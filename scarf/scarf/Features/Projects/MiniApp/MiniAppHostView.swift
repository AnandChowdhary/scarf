import SwiftUI
import WebKit
import ScarfCore
import os

/// Renders one mini-app inside Scarf — a `WKWebView` wired to the
/// directory-scoped `scarf-miniapp://` scheme handler AND the
/// `window.scarf` bridge.
///
/// **Sandboxing:**
/// - Non-persistent data store (no cross-app cookie/localStorage leak).
/// - Assets only via the scheme handler scoped to the mini-app dir.
/// - Navigation locked to `scarf-miniapp://`.
/// - Bridge calls pass through `MiniAppBridgeDispatcher` (default-deny):
///   `grantedPermissions` is empty until the permission-preview sheet
///   ships, so only the ungated baseline surfaces (`context`, `ui.*`) work
///   out of the box; `store` needs the `store` grant; the agent/data
///   channels report `not_implemented`.
struct MiniAppHostView: NSViewRepresentable {
    let project: ScarfProject
    let manifest: MiniAppManifest
    let serverContext: ServerContext
    /// User-approved permissions. Empty = default-deny (the secure default
    /// until the permission-preview sheet supplies grants).
    var grantedPermissions: Set<MiniAppPermission> = []
    /// Optional host handler for `ui.*` actions (toast/close/resize).
    var onUIAction: ((MiniAppUIAction) -> Void)? = nil

    private var projectPath: String { project.rootPath }

    func makeNSView(context: Context) -> WKWebView {
        let baseDir = MiniAppService.miniAppDir(forProjectPath: projectPath, id: manifest.id)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(
            MiniAppSchemeHandler(baseDirectory: baseDir),
            forURLScheme: MiniAppAssetResolver.scheme
        )

        let miniContext = MiniAppContext(
            projectId: project.id.uuidString,
            projectName: project.name,
            projectRoot: project.rootPath,
            serverId: serverContext.id.uuidString,
            miniAppId: manifest.id,
            generated: manifest.generated
        )
        // Dedicated agent session for scarf.prompt — lazy (no hermes acp
        // process until the first granted prompt). Held by the coordinator
        // so dismantleNSView can tear it (and its process) down.
        let agentSession = MiniAppAgentSession(context: serverContext, projectRoot: projectPath)
        context.coordinator.agentSession = agentSession

        let custom = onUIAction
        let bridge = ScarfMiniAppBridge(
            projectPath: projectPath,
            miniAppId: manifest.id,
            serverContext: serverContext,
            dispatcher: MiniAppBridgeDispatcher(grantedPermissions: grantedPermissions),
            store: MiniAppStore(context: serverContext),
            context: miniContext,
            agentSession: agentSession,
            onUIAction: { action in Self.handleUIAction(action, custom: custom) }
        )
        // The userContentController retains the handler; both die with the
        // webview when SwiftUI tears the representable down. The handler
        // holds no strong ref back to the webview, so no cycle.
        config.userContentController.addScriptMessageHandler(
            bridge, contentWorld: .page, name: MiniAppBridge.messageHandlerName
        )
        config.userContentController.addUserScript(WKUserScript(
            source: MiniAppBridge.javaScriptSource(context: miniContext),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        // Let the bridge push streamed agent events into this page (weak ref).
        bridge.webView = webView
        load(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedAppID != manifest.id else { return }
        context.coordinator.loadedAppID = manifest.id
        load(into: webView)
    }

    private func load(into webView: WKWebView) {
        guard let url = URL(string: MiniAppAssetResolver.entryURLString(entry: manifest.entry)) else { return }
        webView.load(URLRequest(url: url))
    }

    /// Default `ui.*` handling: log, then forward to the host's handler.
    private static func handleUIAction(_ action: MiniAppUIAction, custom: ((MiniAppUIAction) -> Void)?) {
        Logger(subsystem: "com.scarf", category: "MiniAppHostView")
            .info("mini-app ui action: \(String(describing: action), privacy: .public)")
        custom?(action)
    }

    /// Tear down the mini-app's agent session (and its `hermes acp`
    /// process) when SwiftUI removes the host — including on `.id`-driven
    /// recreation when permissions change, so a revoked grant doesn't leave
    /// an old session running.
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        let session = coordinator.agentSession
        coordinator.agentSession = nil
        Task { await session?.shutdown() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(appID: manifest.id) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "com.scarf", category: "MiniAppHostView")
        var loadedAppID: String
        var agentSession: MiniAppAgentSession?

        init(appID: String) { self.loadedAppID = appID }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
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
