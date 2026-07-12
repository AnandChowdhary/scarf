import Testing
import Foundation
import ScarfCore
@testable import scarf_mobile

/// gh#124 regression coverage: the iOS chat path must synthesize
/// `.promptComplete` from `sendPrompt`'s return value. The ACP
/// `session/update` stream never carries a completion event — the
/// turn-completion signal IS the `session/prompt` response — so a
/// consumer that discards the result leaves `RichChatViewModel` in
/// the working state forever ("Finishing up…" after the reply landed).
/// This exact bug class shipped twice (MiniAppAgentSession, then the
/// iOS chat controller); this pins the controller side the way
/// `MiniAppAgentSessionTests` pins the mini-app side.
@Suite(.serialized) @MainActor struct ChatControllerPromptCompleteTests {

    // MARK: - Fake channel

    /// In-memory `ACPChannel` that auto-answers the whole handshake AND
    /// `session/prompt` — emitting one `agent_message_chunk` before the
    /// prompt response, mirroring a real Hermes turn (chunks stream
    /// first, the JSON-RPC result lands last).
    actor AutoReplyChannel: ACPChannel {
        static let sessionId = "ios-124"
        static let replyText = "Hello back"

        nonisolated let incoming: AsyncThrowingStream<String, Error>
        nonisolated let stderr: AsyncThrowingStream<String, Error>
        private let incomingCont: AsyncThrowingStream<String, Error>.Continuation
        private let stderrCont: AsyncThrowingStream<String, Error>.Continuation
        private(set) var closed = false

        var diagnosticID: String? { "fake-ios-chat-channel" }
        var isClosed: Bool { closed }

        init() {
            let (inStream, inCont) = AsyncThrowingStream<String, Error>.makeStream()
            let (errStream, errCont) = AsyncThrowingStream<String, Error>.makeStream()
            self.incoming = inStream
            self.incomingCont = inCont
            self.stderr = errStream
            self.stderrCont = errCont
        }

        func send(_ line: String) async throws {
            guard !closed,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = obj["method"] as? String,
                  let id = obj["id"] as? Int
            else { return }
            switch method {
            case "initialize":
                yieldJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
            case "session/new":
                yieldJSON(["jsonrpc": "2.0", "id": id, "result": ["sessionId": Self.sessionId]])
            case "session/prompt":
                // Chunk first, then the result — with a cushion so the
                // event loop handles the chunk before completion, like a
                // real turn.
                yieldJSON([
                    "jsonrpc": "2.0",
                    "method": "session/update",
                    "params": [
                        "sessionId": Self.sessionId,
                        "update": [
                            "sessionUpdate": "agent_message_chunk",
                            "content": ["text": Self.replyText],
                        ] as [String: Any],
                    ] as [String: Any],
                ])
                try? await Task.sleep(nanoseconds: 100_000_000)
                yieldJSON([
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "stopReason": "end_turn",
                        "usage": ["inputTokens": 3, "outputTokens": 5] as [String: Any],
                    ] as [String: Any],
                ])
            default:
                break
            }
        }

        func close() async {
            closed = true
            incomingCont.finish()
            stderrCont.finish()
        }

        private func yieldJSON(_ obj: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: obj),
                  let line = String(data: data, encoding: .utf8) else { return }
            incomingCont.yield(line)
        }
    }

    // MARK: - Test

    @Test func sendFinalizesTurnFromPromptResult() async throws {
        // A fake remote whose "config.yaml" lives in a tmp dir, served by
        // LocalTransport so the model preflight passes hermetically. The
        // nonexistent hermes hint keeps the gh#112 CLI fallbacks from
        // finding the dev machine's real install.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarf-gh124-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try """
        model:
          default: test-model
          provider: test-provider
        """.write(to: tmp.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let config = SSHConfig(
            host: "fake.invalid",
            remoteHome: tmp.path,
            hermesBinaryHint: "/nonexistent/scarf-test-hermes"
        )
        let ctx = ServerContext(id: UUID(), displayName: "fake", kind: .ssh(config))

        let priorFactory = ServerContext.sshTransportFactory
        ServerContext.sshTransportFactory = { id, _, _ in LocalTransport(contextID: id) }
        defer { ServerContext.sshTransportFactory = priorFactory }

        let controller = ChatController(context: ctx)
        controller.clientFactory = { _ in
            ACPClient(context: ctx) { _ in AutoReplyChannel() }
        }

        await controller.start()
        guard case .ready = controller.state else {
            Issue.record("controller did not reach .ready: \(controller.state)")
            return
        }
        #expect(controller.vm.sessionId == AutoReplyChannel.sessionId)

        controller.draft = "hello"
        await controller.send()

        // The heart of gh#124: sendPrompt returned, so the turn must be
        // finalized — no lingering "Finishing up…" state.
        #expect(controller.vm.isAgentWorking == false)
        #expect(controller.vm.isPostProcessing == false)

        // The streaming bubble (id == 0) must have been promoted to a
        // finalized assistant message carrying the streamed text.
        let assistant = controller.vm.messages.last(where: { $0.isAssistant })
        #expect(assistant != nil)
        #expect(assistant?.id != 0)
        #expect(assistant?.content.contains(AutoReplyChannel.replyText) == true)
    }
}
