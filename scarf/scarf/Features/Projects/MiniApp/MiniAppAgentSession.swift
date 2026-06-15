import Foundation
import ScarfCore
import os

/// Owns a dedicated, project-scoped ACP session for one running mini-app —
/// the backing for `scarf.prompt`.
///
/// **Isolation.** The mini-app gets its OWN `hermes acp` session (cwd =
/// project root), spawned lazily on the first prompt and torn down on
/// `shutdown()`. It never shares a chat's session, so web content can't
/// reach into other conversations. The session is reachable only after the
/// user grants the (sensitive) `prompt` permission.
///
/// **Request/response.** `prompt(_:)` sends the text and resolves with the
/// agent's full reply, accumulated from the streamed `messageChunk` events
/// and finalized on `promptComplete` (the same completion signal the chat
/// UI relies on). One prompt in flight at a time; a launch/timeout failure
/// from `sendPrompt` fails the pending call.
///
/// **Runaway protection.** A host-side sliding-window rate limit caps how
/// often web content can drive the agent.
actor MiniAppAgentSession {
    private static let logger = Logger(subsystem: "com.scarf", category: "MiniAppAgentSession")

    private let context: ServerContext
    private let projectRoot: String
    private let rateLimiter = MiniAppRateLimiter(maxEvents: 8, windowSeconds: 60)
    private var promptHistory: [Date] = []

    private var client: ACPClient?
    private var sessionId: String?
    private var eventLoop: Task<Void, Never>?

    // At most one prompt in flight; the event loop resolves it.
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var pendingBuffer = ""

    init(context: ServerContext, projectRoot: String) {
        self.context = context
        self.projectRoot = projectRoot
    }

    enum AgentError: LocalizedError {
        case rateLimited
        case busy
        case cancelled
        case connectionLost(String)

        var errorDescription: String? {
            switch self {
            case .rateLimited: return "Mini-app exceeded its prompt rate limit; try again shortly."
            case .busy: return "A prompt is already running for this mini-app."
            case .cancelled: return "The mini-app session was closed."
            case .connectionLost(let r): return "Agent connection lost: \(r)"
            }
        }
    }

    /// Send `text` to the mini-app's agent and resolve with the full reply.
    func prompt(_ text: String) async throws -> String {
        let (allowed, history) = rateLimiter.decide(now: Date(), history: promptHistory)
        promptHistory = history
        guard allowed else { throw AgentError.rateLimited }
        guard pendingContinuation == nil else { throw AgentError.busy }

        let (client, sid) = try await ensureSession()
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            pendingBuffer = ""
            // Kick off the prompt. Completion arrives via the event loop's
            // .promptComplete; this task only needs to surface a launch /
            // timeout / transport failure.
            Task {
                do {
                    _ = try await client.sendPrompt(sessionId: sid, text: text)
                } catch {
                    await self.failPending(error)
                }
            }
        }
    }

    /// Tear down the ACP session + process. Idempotent.
    func shutdown() async {
        eventLoop?.cancel()
        eventLoop = nil
        if let continuation = pendingContinuation {
            continuation.resume(throwing: AgentError.cancelled)
            pendingContinuation = nil
            pendingBuffer = ""
        }
        if let client {
            await client.stop()
        }
        client = nil
        sessionId = nil
    }

    // MARK: - Private

    private func ensureSession() async throws -> (ACPClient, String) {
        if let client, let sessionId { return (client, sessionId) }
        let newClient = ACPClient.forMacApp(context: context)
        try await newClient.start()
        let sid = try await newClient.newSession(cwd: projectRoot)
        client = newClient
        sessionId = sid
        startEventLoop(client: newClient, sessionId: sid)
        Self.logger.info("mini-app agent session started for \(self.projectRoot, privacy: .public)")
        return (newClient, sid)
    }

    private func startEventLoop(client: ACPClient, sessionId: String) {
        eventLoop = Task { [weak self] in
            let stream = await client.events
            for await event in stream {
                guard let self else { break }
                // Only this session's events (or connection-level ones).
                if event.sessionId == sessionId || event.sessionId == nil {
                    await self.handle(event)
                }
            }
        }
    }

    private func handle(_ event: ACPEvent) {
        switch event {
        case .messageChunk(_, let text):
            if pendingContinuation != nil { pendingBuffer += text }
        case .promptComplete:
            resumePending(.success(pendingBuffer))
        case .connectionLost(let reason):
            resumePending(.failure(AgentError.connectionLost(reason)))
        default:
            break
        }
    }

    private func failPending(_ error: Error) {
        resumePending(.failure(error))
    }

    /// Resolve the in-flight prompt exactly once (first signal wins).
    private func resumePending(_ result: Result<String, Error>) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        let buffer = pendingBuffer
        pendingBuffer = ""
        switch result {
        case .success: continuation.resume(returning: buffer)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
