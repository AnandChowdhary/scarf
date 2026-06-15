import Foundation
import WebKit
import ScarfCore
import os

/// Host-side `window.scarf` bridge — the `WKScriptMessageHandlerWithReply`
/// that backs the JS shim. Decodes each `{method, args}` message, runs it
/// through `MiniAppBridgeDispatcher.preflight` (the default-deny trust
/// boundary in ScarfCore), and — only if authorized + implemented —
/// executes the handler and replies. A denied call rejects the JS promise
/// with `code: message`; nothing reaches a service before the gate.
///
/// This increment wires the safe surfaces: `context`, `store` (sandboxed
/// KV), and the benign `ui.*` affordances. The agent (`prompt`/`events`)
/// and data (`query`/`file`/`kanban`) channels are gated and report
/// `not_implemented` until their follow-on increments.
final class ScarfMiniAppBridge: NSObject, WKScriptMessageHandlerWithReply {
    private static let logger = Logger(subsystem: "com.scarf", category: "ScarfMiniAppBridge")

    private let projectPath: String
    private let miniAppId: String
    private let dispatcher: MiniAppBridgeDispatcher
    private let store: MiniAppStore
    private let contextJSON: String
    /// Dedicated agent session backing `scarf.prompt`. Lazily spawns its
    /// own `hermes acp` on first use; `nil` only in contexts that never
    /// grant `prompt`.
    private let agentSession: MiniAppAgentSession?
    /// Invoked on the main thread for `ui.*` calls. Host wires real UI
    /// (toast/close) later; defaults to logging.
    private let onUIAction: (MiniAppUIAction) -> Void

    init(
        projectPath: String,
        miniAppId: String,
        dispatcher: MiniAppBridgeDispatcher,
        store: MiniAppStore,
        context: MiniAppContext,
        agentSession: MiniAppAgentSession?,
        onUIAction: @escaping (MiniAppUIAction) -> Void
    ) {
        self.projectPath = projectPath
        self.miniAppId = miniAppId
        self.dispatcher = dispatcher
        self.store = store
        self.agentSession = agentSession
        self.onUIAction = onUIAction
        if let data = try? JSONEncoder().encode(context), let json = String(data: data, encoding: .utf8) {
            self.contextJSON = json
        } else {
            self.contextJSON = "{}"
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        // Called on the main thread by WebKit.
        guard let body = message.body as? [String: Any],
              let methodString = body["method"] as? String,
              let method = MiniAppBridgeMethod(rawValue: methodString) else {
            replyHandler(nil, "bad_request: malformed bridge message")
            return
        }
        let args = (body["args"] as? [String]) ?? (body["args"] as? [Any])?.compactMap { $0 as? String } ?? []

        // The trust boundary: deny anything not granted / not implemented.
        if let denial = dispatcher.preflight(method) {
            replyHandler(nil, "\(denial.errorCode ?? "error"): \(denial.errorMessage ?? "")")
            return
        }

        switch method {
        case .contextGet:
            replyHandler(contextJSON, nil)

        case .storeGet:
            guard let key = args.first else { replyHandler(nil, "bad_request: store.get needs a key"); return }
            let store = store, projectPath = projectPath, id = miniAppId
            DispatchQueue.global(qos: .userInitiated).async {
                let value = store.get(projectPath: projectPath, miniAppId: id, key: key)
                DispatchQueue.main.async { replyHandler(value, nil) }
            }

        case .storeSet:
            guard args.count >= 2 else { replyHandler(nil, "bad_request: store.set needs key and value"); return }
            let key = args[0], value = args[1]
            let store = store, projectPath = projectPath, id = miniAppId
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try store.set(projectPath: projectPath, miniAppId: id, key: key, value: value)
                    DispatchQueue.main.async { replyHandler(nil, nil) }
                } catch {
                    DispatchQueue.main.async { replyHandler(nil, "internal_error: \(error.localizedDescription)") }
                }
            }

        case .uiToast:
            onUIAction(.toast(args.first ?? ""))
            replyHandler(nil, nil)
        case .uiSetTitle:
            onUIAction(.setTitle(args.first ?? ""))
            replyHandler(nil, nil)
        case .uiResize:
            onUIAction(.resize(width: args.count > 0 ? Double(args[0]) : nil,
                               height: args.count > 1 ? Double(args[1]) : nil))
            replyHandler(nil, nil)
        case .uiRequestClose:
            onUIAction(.requestClose)
            replyHandler(nil, nil)

        case .promptSend:
            guard let agentSession else {
                replyHandler(nil, "internal_error: no agent session bound")
                return
            }
            let text = args.first ?? ""
            Task {
                do {
                    let reply = try await agentSession.prompt(text)
                    await MainActor.run { replyHandler(reply, nil) }
                } catch {
                    await MainActor.run { replyHandler(nil, "error: \(error.localizedDescription)") }
                }
            }

        case .eventsSubscribe, .query, .fileRead, .kanbanRead:
            // Unreachable: preflight already returned not_implemented for
            // these. Defensive fallback keeps the switch exhaustive.
            replyHandler(nil, "not_implemented: \(method.rawValue)")
        }
    }
}

/// A `ui.*` action a mini-app requested. The host decides how to surface
/// each (toast banner, window title, panel resize, close request).
enum MiniAppUIAction: Sendable {
    case toast(String)
    case setTitle(String)
    case resize(width: Double?, height: Double?)
    case requestClose
}
