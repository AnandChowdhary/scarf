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

    /// Largest project file `scarf.file.read` will return.
    private static let maxFileReadBytes = 4 * 1024 * 1024

    private let projectPath: String
    private let miniAppId: String
    private let serverContext: ServerContext
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
    /// Set by the host once the webview exists, so streamed agent events can
    /// be pushed into the page. Weak: the userContentController already
    /// retains this handler, so a strong ref back would cycle.
    weak var webView: WKWebView?

    init(
        projectPath: String,
        miniAppId: String,
        serverContext: ServerContext,
        dispatcher: MiniAppBridgeDispatcher,
        store: MiniAppStore,
        context: MiniAppContext,
        agentSession: MiniAppAgentSession?,
        onUIAction: @escaping (MiniAppUIAction) -> Void
    ) {
        self.projectPath = projectPath
        self.miniAppId = miniAppId
        self.serverContext = serverContext
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

        case .eventsSubscribe:
            guard let agentSession else {
                replyHandler(nil, "internal_error: no agent session bound")
                return
            }
            Task {
                await agentSession.setEventSink { [weak self] event in
                    self?.emitToWeb(event)
                }
                await MainActor.run { replyHandler(nil, nil) }
            }

        case .fileRead:
            // Read-only, contained to the project root via the same
            // symlink-hardened resolver the asset server uses.
            guard let rel = args.first else {
                replyHandler(nil, "bad_request: file.read needs a path"); return
            }
            let projectPath = projectPath
            DispatchQueue.global(qos: .userInitiated).async {
                guard let path = MiniAppAssetResolver.containedFilePath(requestPath: rel, baseDirectory: projectPath),
                      let data = FileManager.default.contents(atPath: path),
                      data.count <= Self.maxFileReadBytes,
                      let text = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        replyHandler(nil, "not_found: file is missing, too large, outside the project, or not UTF-8 text")
                    }
                    return
                }
                DispatchQueue.main.async { replyHandler(text, nil) }
            }

        case .query:
            // query's permission is the kind-specific query:<kind>, so it's
            // gated here (preflight passes it through with a nil static perm).
            guard let kind = args.first else {
                replyHandler(nil, "bad_request: query needs a kind"); return
            }
            guard dispatcher.grantedPermissions.contains(.query(kind)) else {
                replyHandler(nil, "permission_denied: query:\(kind) is not granted")
                return
            }
            handleQuery(kind: kind, replyHandler: replyHandler)

        case .kanbanRead:
            // Gated by preflight on query:kanban.tasks.
            handleQuery(kind: "kanban.tasks", replyHandler: replyHandler)
        }
    }

    // MARK: - Event streaming (scarf.onEvent)

    /// Push one streamed agent event into the page (main thread). Called
    /// from the agent session's sink; a closed mini-app (weak webview)
    /// silently drops late events.
    private func emitToWeb(_ event: ACPEvent) {
        guard let json = Self.eventJSON(event) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.__scarfEmit(\(json))", completionHandler: nil)
        }
    }

    /// Serialize the subset of agent events a mini-app renders into a JSON
    /// literal. Returns `nil` for events that aren't forwarded (e.g.
    /// permission requests, which are auto-handled host-side).
    private static func eventJSON(_ event: ACPEvent) -> String? {
        let obj: [String: Any]
        switch event {
        case .messageChunk(_, let text): obj = ["type": "message", "text": text]
        case .thoughtChunk(_, let text): obj = ["type": "thought", "text": text]
        case .toolCallStart(_, let call): obj = ["type": "tool", "title": call.title, "status": call.status]
        case .toolCallUpdate: obj = ["type": "tool_update"]
        case .promptComplete: obj = ["type": "complete"]
        default: return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    // MARK: - Data channel (scarf.query / scarf.kanban)

    /// Resolve a whitelisted, read-only data `kind` to a JSON array string.
    /// v1 serves `kanban.tasks` (project-scoped, Codable). Sensitive kinds
    /// (sessions/messages/insights) are deferred pending a privacy review —
    /// chat content must not be exposed to untrusted web content lightly.
    private func handleQuery(kind: String, replyHandler: @escaping (Any?, String?) -> Void) {
        switch kind {
        case "kanban.tasks":
            let ctx = serverContext
            let projectPath = projectPath
            Task {
                do {
                    // Scope to the project's kanban tenant; no tenant → no
                    // project board yet → empty result.
                    guard let tenant = KanbanTenantReader(context: ctx).tenant(forProjectPath: projectPath) else {
                        await MainActor.run { replyHandler("[]", nil) }
                        return
                    }
                    let tasks = try await KanbanService(context: ctx).list(KanbanListFilter(tenant: tenant))
                    let json = String(data: try JSONEncoder().encode(tasks), encoding: .utf8) ?? "[]"
                    await MainActor.run { replyHandler(json, nil) }
                } catch {
                    await MainActor.run { replyHandler(nil, "internal_error: \(error.localizedDescription)") }
                }
            }
        default:
            replyHandler(nil, "not_implemented: query:\(kind) is not available in this build")
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
