import AVFoundation
import Foundation
import Observation
import Security

enum OpenAIRealtimeVoiceError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case microphoneDenied
    case recordingFailed
    case emptyRecording
    case malformedRecording
    case invalidServerEvent
    case emptyTranscript
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key to use Voice mode."
        case .invalidAPIKey:
            return "Enter a valid OpenAI API key."
        case .microphoneDenied:
            return "Microphone access is off. Enable it for Scarf in System Settings → Privacy & Security → Microphone."
        case .recordingFailed:
            return "Scarf couldn't start microphone recording."
        case .emptyRecording:
            return "No speech was recorded. Try again and speak after the mic turns red."
        case .malformedRecording:
            return "Scarf couldn't read the recorded audio."
        case .invalidServerEvent:
            return "OpenAI returned an unreadable Realtime event."
        case .emptyTranscript:
            return "OpenAI didn't detect any speech."
        case .api(let message):
            return message
        }
    }
}

/// Device-local storage for the user's bring-your-own OpenAI key.
/// The credential never enters UserDefaults, repository files, or logs.
enum OpenAIRealtimeAPIKeyStore {
    private static let service = "com.scarf.openai-realtime"
    private static let account = "api-key"

    static func load() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw OpenAIRealtimeVoiceError.api("Scarf couldn't read the OpenAI key from Keychain.")
        }
        return value
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-"), trimmed.count > 10 else {
            throw OpenAIRealtimeVoiceError.invalidAPIKey
        }
        let lookup: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [kSecValueData: Data(trimmed.utf8)]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw OpenAIRealtimeVoiceError.api("Scarf couldn't update the OpenAI key in Keychain.")
        }
        var add = lookup
        add[kSecValueData] = Data(trimmed.utf8)
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIRealtimeVoiceError.api("Scarf couldn't save the OpenAI key in Keychain.")
        }
    }

    static func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIRealtimeVoiceError.api("Scarf couldn't remove the OpenAI key from Keychain.")
        }
    }
}

/// Small, testable boundary for the GA Realtime event shapes used by Voice mode.
enum OpenAIRealtimeProtocol {
    struct ServerEvent: Decodable, Sendable, Equatable {
        struct APIError: Decodable, Sendable, Equatable {
            let message: String?
        }

        let type: String
        let delta: String?
        let text: String?
        let transcript: String?
        let error: APIError?
    }

    static func decode(_ text: String) throws -> ServerEvent {
        guard let data = text.data(using: .utf8) else {
            throw OpenAIRealtimeVoiceError.invalidServerEvent
        }
        do {
            return try JSONDecoder().decode(ServerEvent.self, from: data)
        } catch {
            throw OpenAIRealtimeVoiceError.invalidServerEvent
        }
    }

    static func transcriptionSessionUpdate() throws -> String {
        try encode([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": "gpt-realtime",
                "output_modalities": ["text"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": [
                            "model": "gpt-realtime-whisper",
                            "delay": "low"
                        ],
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ])
    }

    static func speechSessionUpdate() throws -> String {
        try encode([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": "gpt-realtime",
                "output_modalities": ["audio"],
                "instructions": "Read the supplied assistant response aloud faithfully. Do not add, remove, answer, summarize, or comment on its content.",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "turn_detection": NSNull()
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "voice": "marin"
                    ]
                ]
            ]
        ])
    }

    static func appendAudio(_ data: Data) throws -> String {
        try encode([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
    }

    static func commitAudio() throws -> String {
        try encode(["type": "input_audio_buffer.commit"])
    }

    static func createSpeechItem(_ text: String) throws -> String {
        try encode([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": "Read the text below aloud exactly as written.\n\n\(text)"
                ]]
            ]
        ])
    }

    static func createAudioResponse() throws -> String {
        try encode([
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"],
                "instructions": "Act only as a speech renderer. Read the text in the user's message aloud verbatim. Do not answer it, acknowledge it, summarize it, or add any words."
            ]
        ])
    }

    private static func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenAIRealtimeVoiceError.invalidServerEvent
        }
        return text
    }
}

/// Extracts the raw little-endian PCM payload from AVAudioRecorder's WAV file.
enum WAVPCM16 {
    static func extract(from data: Data) throws -> Data {
        guard data.count >= 12,
              ascii(in: data, range: 0..<4) == "RIFF",
              ascii(in: data, range: 8..<12) == "WAVE" else {
            throw OpenAIRealtimeVoiceError.malformedRecording
        }

        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = ascii(in: data, range: offset..<(offset + 4))
            let size = Int(littleEndianUInt32(in: data, at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= data.count else {
                throw OpenAIRealtimeVoiceError.malformedRecording
            }
            if chunkID == "data" {
                guard size >= 2 else { throw OpenAIRealtimeVoiceError.emptyRecording }
                return data.subdata(in: payloadStart..<payloadEnd)
            }
            offset = payloadEnd + (size.isMultiple(of: 2) ? 0 : 1)
        }
        throw OpenAIRealtimeVoiceError.malformedRecording
    }

    private static func ascii(in data: Data, range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { return nil }
        return String(data: data.subdata(in: range), encoding: .ascii)
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data[offset..<(offset + 4)].enumerated().reduce(0) { partial, pair in
            partial | (UInt32(pair.element) << UInt32(pair.offset * 8))
        }
    }
}

actor OpenAIRealtimeClient {
    private static let audioChunkBytes = 24_000

    func transcribe(apiKey: String, pcm: Data) async throws -> String {
        let connection = makeConnection(apiKey: apiKey, model: "gpt-realtime")
        defer { connection.close() }
        try await waitUntilReady(connection.socket)
        try await send(OpenAIRealtimeProtocol.transcriptionSessionUpdate(), to: connection.socket)
        try await waitUntilUpdated(connection.socket)

        var offset = 0
        while offset < pcm.count {
            let end = min(offset + Self.audioChunkBytes, pcm.count)
            try await send(
                OpenAIRealtimeProtocol.appendAudio(pcm.subdata(in: offset..<end)),
                to: connection.socket
            )
            offset = end
        }
        try await send(OpenAIRealtimeProtocol.commitAudio(), to: connection.socket)

        var transcript = ""
        while true {
            let event = try await receive(from: connection.socket)
            switch event.type {
            case "conversation.item.input_audio_transcription.delta":
                transcript += event.delta ?? ""
            case "conversation.item.input_audio_transcription.completed":
                if let completed = event.transcript, !completed.isEmpty {
                    transcript = completed
                }
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw OpenAIRealtimeVoiceError.emptyTranscript }
                return trimmed
            case "error":
                throw OpenAIRealtimeVoiceError.api(event.error?.message ?? "OpenAI Realtime transcription failed.")
            default:
                continue
            }
        }
    }

    func speak(
        apiKey: String,
        text: String,
        onAudioChunk: @escaping @Sendable (Data) async -> Void
    ) async throws {
        let connection = makeConnection(apiKey: apiKey, model: "gpt-realtime")
        defer { connection.close() }
        try await waitUntilReady(connection.socket)
        try await send(OpenAIRealtimeProtocol.speechSessionUpdate(), to: connection.socket)
        try await waitUntilUpdated(connection.socket)
        try await send(OpenAIRealtimeProtocol.createSpeechItem(text), to: connection.socket)
        try await send(OpenAIRealtimeProtocol.createAudioResponse(), to: connection.socket)

        while true {
            let event = try await receive(from: connection.socket)
            switch event.type {
            case "response.output_audio.delta":
                if let encoded = event.delta, let chunk = Data(base64Encoded: encoded) {
                    await onAudioChunk(chunk)
                }
            case "response.done":
                return
            case "error":
                throw OpenAIRealtimeVoiceError.api(event.error?.message ?? "OpenAI Realtime speech failed.")
            default:
                continue
            }
        }
    }

    private func makeConnection(apiKey: String, model: String) -> Connection {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return Connection(session: session, socket: socket)
    }

    private func waitUntilReady(_ socket: URLSessionWebSocketTask) async throws {
        try await wait(for: "session.created", socket: socket)
    }

    private func waitUntilUpdated(_ socket: URLSessionWebSocketTask) async throws {
        try await wait(for: "session.updated", socket: socket)
    }

    private func wait(for expectedType: String, socket: URLSessionWebSocketTask) async throws {
        while true {
            let event = try await receive(from: socket)
            if event.type == expectedType { return }
            if event.type == "error" {
                throw OpenAIRealtimeVoiceError.api(event.error?.message ?? "OpenAI Realtime connection failed.")
            }
        }
    }

    private func send(_ text: String, to socket: URLSessionWebSocketTask) async throws {
        try await socket.send(.string(text))
    }

    private func receive(from socket: URLSessionWebSocketTask) async throws -> OpenAIRealtimeProtocol.ServerEvent {
        let message = try await socket.receive()
        switch message {
        case .string(let text):
            return try OpenAIRealtimeProtocol.decode(text)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw OpenAIRealtimeVoiceError.invalidServerEvent
            }
            return try OpenAIRealtimeProtocol.decode(text)
        @unknown default:
            throw OpenAIRealtimeVoiceError.invalidServerEvent
        }
    }

    private struct Connection {
        let session: URLSession
        let socket: URLSessionWebSocketTask

        func close() {
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }
    }
}

@MainActor
final class RealtimeMicrophoneRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    var duration: TimeInterval { recorder?.currentTime ?? 0 }

    func start() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw OpenAIRealtimeVoiceError.microphoneDenied
            }
        default:
            throw OpenAIRealtimeVoiceError.microphoneDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarf-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard newRecorder.prepareToRecord(), newRecorder.record() else {
            throw OpenAIRealtimeVoiceError.recordingFailed
        }
        fileURL = url
        recorder = newRecorder
    }

    func stopAndReadPCM() throws -> Data {
        guard let recorder, let fileURL else {
            throw OpenAIRealtimeVoiceError.recordingFailed
        }
        let capturedDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard capturedDuration >= 0.15 else { throw OpenAIRealtimeVoiceError.emptyRecording }
        return try WAVPCM16.extract(from: Data(contentsOf: fileURL))
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
}

@MainActor
final class RealtimePCMStreamPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private var pendingBuffers = 0
    private var streamEnded = false
    private var drainContinuation: CheckedContinuation<Void, Never>?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        stop()
        engine.prepare()
        try engine.start()
    }

    func enqueue(_ data: Data) {
        guard !data.isEmpty else { return }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.int16ChannelData?[0] else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            memcpy(channel, source, Int(frameCount) * MemoryLayout<Int16>.size)
        }
        buffer.frameLength = frameCount
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.bufferDidFinish()
            }
        }
        if !player.isPlaying { player.play() }
    }

    func finish() async {
        streamEnded = true
        guard pendingBuffers > 0 else { return }
        await withCheckedContinuation { continuation in
            drainContinuation = continuation
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        pendingBuffers = 0
        streamEnded = false
        drainContinuation?.resume()
        drainContinuation = nil
    }

    private func bufferDidFinish() {
        pendingBuffers = max(0, pendingBuffers - 1)
        if streamEnded, pendingBuffers == 0 {
            drainContinuation?.resume()
            drainContinuation = nil
        }
    }
}

@MainActor
@Observable
final class RealtimeVoiceController {
    enum ComposerMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case voice = "Voice"

        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case waitingForHermes
        case speaking
    }

    var mode: ComposerMode = .text
    private(set) var phase: Phase = .idle
    private(set) var hasAPIKey = false
    var showsCredentialSheet = false
    var apiKeyDraft = ""
    private(set) var errorMessage: String?

    private let microphone = RealtimeMicrophoneRecorder()
    private let player = RealtimePCMStreamPlayer()
    private let client = OpenAIRealtimeClient()
    private var operationTask: Task<Void, Never>?
    private var awaitingHermesReply = false
    private var pendingHermesSessionID: String?
    private var lastSpokenMessageID: Int?

    init() {
        hasAPIKey = (try? OpenAIRealtimeAPIKeyStore.load()) != nil
    }

    var statusTitle: String {
        switch phase {
        case .idle: return "Tap the microphone to speak"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing with gpt-realtime-whisper…"
        case .waitingForHermes: return "Hermes is responding…"
        case .speaking: return "Speaking Hermes's response…"
        }
    }

    var statusDetail: String {
        switch phase {
        case .idle: return "Your words are sent through this Hermes chat."
        case .recording: return "Tap again to send your recording."
        case .transcribing: return "The transcript will appear as your next message."
        case .waitingForHermes: return "Tools, permissions, and memory still run through Hermes."
        case .speaking: return "Tap the speaker stop control to interrupt playback."
        }
    }

    var canRecord: Bool { phase == .idle || phase == .recording }

    func selectMode(_ newMode: ComposerMode) {
        if newMode == .voice, !hasAPIKey {
            apiKeyDraft = ""
            showsCredentialSheet = true
            return
        }
        if newMode == .text { resetVoiceTurn() }
        mode = newMode
    }

    func saveAPIKey() {
        do {
            try OpenAIRealtimeAPIKeyStore.save(apiKeyDraft)
            apiKeyDraft = ""
            hasAPIKey = true
            errorMessage = nil
            showsCredentialSheet = false
            mode = .voice
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func forgetAPIKey() {
        do {
            try OpenAIRealtimeAPIKeyStore.delete()
            hasAPIKey = false
            apiKeyDraft = ""
            showsCredentialSheet = false
            mode = .text
            resetVoiceTurn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleRecording(onTranscript: @escaping @MainActor (String) -> Void) {
        guard mode == .voice else { return }
        errorMessage = nil
        switch phase {
        case .idle:
            operationTask?.cancel()
            operationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await microphone.start()
                    phase = .recording
                } catch {
                    phase = .idle
                    errorMessage = error.localizedDescription
                }
            }
        case .recording:
            operationTask?.cancel()
            operationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let pcm = try microphone.stopAndReadPCM()
                    guard let apiKey = try OpenAIRealtimeAPIKeyStore.load() else {
                        throw OpenAIRealtimeVoiceError.missingAPIKey
                    }
                    phase = .transcribing
                    let transcript = try await client.transcribe(apiKey: apiKey, pcm: pcm)
                    awaitingHermesReply = true
                    phase = .waitingForHermes
                    onTranscript(transcript)
                } catch {
                    phase = .idle
                    errorMessage = error.localizedDescription
                }
            }
        default:
            break
        }
    }

    /// Called by the shared composer send closure. Text-mode sends are a
    /// no-op; only a transcript that just entered the normal Hermes path
    /// binds the pending spoken reply to its originating session.
    func noteHermesSend(sessionID: String?) {
        guard awaitingHermesReply else { return }
        pendingHermesSessionID = sessionID
    }

    /// A nil → id transition is expected when a voice prompt creates a new
    /// Hermes chat. Any other session switch while a turn is pending cancels
    /// voice playback so the new chat can never speak the old chat's reply.
    func handleSessionChange(to sessionID: String?) {
        if awaitingHermesReply {
            if pendingHermesSessionID == nil {
                pendingHermesSessionID = sessionID
            } else if pendingHermesSessionID != sessionID {
                resetVoiceTurn()
            }
        } else if phase == .speaking {
            resetVoiceTurn()
        }
    }

    func speakHermesReply(sessionID: String?, messageID: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .voice,
              awaitingHermesReply,
              pendingHermesSessionID == nil || pendingHermesSessionID == sessionID,
              !trimmed.isEmpty,
              lastSpokenMessageID != messageID else { return }
        awaitingHermesReply = false
        pendingHermesSessionID = nil
        lastSpokenMessageID = messageID
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try OpenAIRealtimeAPIKeyStore.load() else {
                    throw OpenAIRealtimeVoiceError.missingAPIKey
                }
                phase = .speaking
                try player.start()
                try await client.speak(apiKey: apiKey, text: trimmed) { [weak self] chunk in
                    await self?.enqueueAudio(chunk)
                }
                await player.finish()
                phase = .idle
            } catch is CancellationError {
                player.stop()
                phase = .idle
            } catch {
                player.stop()
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopSpeaking() {
        guard phase == .speaking else { return }
        operationTask?.cancel()
        player.stop()
        phase = .idle
    }

    func resetVoiceTurn() {
        operationTask?.cancel()
        operationTask = nil
        microphone.cancel()
        player.stop()
        awaitingHermesReply = false
        pendingHermesSessionID = nil
        phase = .idle
        errorMessage = nil
    }

    private func enqueueAudio(_ data: Data) {
        guard phase == .speaking else { return }
        player.enqueue(data)
    }
}
