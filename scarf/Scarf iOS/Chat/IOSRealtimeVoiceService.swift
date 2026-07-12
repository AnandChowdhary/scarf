import AVFoundation
import Foundation
import Observation
import Security

enum IOSRealtimeVoiceError: LocalizedError, Sendable {
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
            return "Microphone access is off. Enable it for ScarfGo in Settings → Privacy & Security → Microphone."
        case .recordingFailed:
            return "ScarfGo couldn't start microphone recording."
        case .emptyRecording:
            return "No speech was recorded. Try again and speak after the mic turns red."
        case .malformedRecording:
            return "ScarfGo couldn't read the recorded audio."
        case .invalidServerEvent:
            return "OpenAI returned an unreadable Realtime event."
        case .emptyTranscript:
            return "OpenAI didn't detect any speech."
        case .api(let message):
            return message
        }
    }
}

enum IOSRealtimeAPIKeyStore {
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
            throw IOSRealtimeVoiceError.api("ScarfGo couldn't read the OpenAI key from Keychain.")
        }
        return value
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-"), trimmed.count > 10 else {
            throw IOSRealtimeVoiceError.invalidAPIKey
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
            throw IOSRealtimeVoiceError.api("ScarfGo couldn't update the OpenAI key in Keychain.")
        }
        var add = lookup
        add[kSecValueData] = Data(trimmed.utf8)
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw IOSRealtimeVoiceError.api("ScarfGo couldn't save the OpenAI key in Keychain.")
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
            throw IOSRealtimeVoiceError.api("ScarfGo couldn't remove the OpenAI key from Keychain.")
        }
    }
}

enum IOSRealtimeProtocol {
    struct ServerEvent: Decodable, Sendable {
        struct APIError: Decodable, Sendable { let message: String? }
        let type: String
        let delta: String?
        let transcript: String?
        let error: APIError?
    }

    static func decode(_ text: String) throws -> ServerEvent {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else {
            throw IOSRealtimeVoiceError.invalidServerEvent
        }
        return event
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
                        "transcription": ["model": "gpt-realtime-whisper", "delay": "low"],
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
        try encode(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
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
            throw IOSRealtimeVoiceError.invalidServerEvent
        }
        return text
    }
}

enum IOSWAVPCM16 {
    static func extract(from data: Data) throws -> Data {
        guard data.count >= 12,
              ascii(in: data, range: 0..<4) == "RIFF",
              ascii(in: data, range: 8..<12) == "WAVE" else {
            throw IOSRealtimeVoiceError.malformedRecording
        }
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = ascii(in: data, range: offset..<(offset + 4))
            let size = Int(littleEndianUInt32(in: data, at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= data.count else { throw IOSRealtimeVoiceError.malformedRecording }
            if chunkID == "data" {
                guard size >= 2 else { throw IOSRealtimeVoiceError.emptyRecording }
                return data.subdata(in: payloadStart..<payloadEnd)
            }
            offset = payloadEnd + (size.isMultiple(of: 2) ? 0 : 1)
        }
        throw IOSRealtimeVoiceError.malformedRecording
    }

    private static func ascii(in data: Data, range: Range<Int>) -> String? {
        guard range.upperBound <= data.count else { return nil }
        return String(data: data.subdata(in: range), encoding: .ascii)
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data[offset..<(offset + 4)].enumerated().reduce(0) { partial, pair in
            partial | (UInt32(pair.element) << UInt32(pair.offset * 8))
        }
    }
}

actor IOSRealtimeClient {
    private static let audioChunkBytes = 24_000

    func transcribe(apiKey: String, pcm: Data) async throws -> String {
        let connection = makeConnection(apiKey: apiKey)
        defer { connection.close() }
        try await wait(for: "session.created", socket: connection.socket)
        try await send(IOSRealtimeProtocol.transcriptionSessionUpdate(), to: connection.socket)
        try await wait(for: "session.updated", socket: connection.socket)
        var offset = 0
        while offset < pcm.count {
            let end = min(offset + Self.audioChunkBytes, pcm.count)
            try await send(IOSRealtimeProtocol.appendAudio(pcm.subdata(in: offset..<end)), to: connection.socket)
            offset = end
        }
        try await send(IOSRealtimeProtocol.commitAudio(), to: connection.socket)

        var transcript = ""
        while true {
            let event = try await receive(from: connection.socket)
            switch event.type {
            case "conversation.item.input_audio_transcription.delta":
                transcript += event.delta ?? ""
            case "conversation.item.input_audio_transcription.completed":
                if let completed = event.transcript, !completed.isEmpty { transcript = completed }
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw IOSRealtimeVoiceError.emptyTranscript }
                return trimmed
            case "error":
                throw IOSRealtimeVoiceError.api(event.error?.message ?? "OpenAI Realtime transcription failed.")
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
        let connection = makeConnection(apiKey: apiKey)
        defer { connection.close() }
        try await wait(for: "session.created", socket: connection.socket)
        try await send(IOSRealtimeProtocol.speechSessionUpdate(), to: connection.socket)
        try await wait(for: "session.updated", socket: connection.socket)
        try await send(IOSRealtimeProtocol.createSpeechItem(text), to: connection.socket)
        try await send(IOSRealtimeProtocol.createAudioResponse(), to: connection.socket)
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
                throw IOSRealtimeVoiceError.api(event.error?.message ?? "OpenAI Realtime speech failed.")
            default:
                continue
            }
        }
    }

    private func makeConnection(apiKey: String) -> Connection {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: "gpt-realtime")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return Connection(session: session, socket: socket)
    }

    private func wait(for expectedType: String, socket: URLSessionWebSocketTask) async throws {
        while true {
            let event = try await receive(from: socket)
            if event.type == expectedType { return }
            if event.type == "error" {
                throw IOSRealtimeVoiceError.api(event.error?.message ?? "OpenAI Realtime connection failed.")
            }
        }
    }

    private func send(_ text: String, to socket: URLSessionWebSocketTask) async throws {
        try await socket.send(.string(text))
    }

    private func receive(from socket: URLSessionWebSocketTask) async throws -> IOSRealtimeProtocol.ServerEvent {
        switch try await socket.receive() {
        case .string(let text):
            return try IOSRealtimeProtocol.decode(text)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw IOSRealtimeVoiceError.invalidServerEvent
            }
            return try IOSRealtimeProtocol.decode(text)
        @unknown default:
            throw IOSRealtimeVoiceError.invalidServerEvent
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
final class IOSRealtimeMicrophoneRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        let granted: Bool
        switch session.recordPermission {
        case .granted:
            granted = true
        case .denied:
            granted = false
        case .undetermined:
            granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default:
            granted = false
        }
        guard granted else { throw IOSRealtimeVoiceError.microphoneDenied }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarfgo-voice-\(UUID().uuidString)")
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
            throw IOSRealtimeVoiceError.recordingFailed
        }
        fileURL = url
        recorder = newRecorder
    }

    func stopAndReadPCM() throws -> Data {
        guard let recorder, let fileURL else { throw IOSRealtimeVoiceError.recordingFailed }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard duration >= 0.15 else { throw IOSRealtimeVoiceError.emptyRecording }
        return try IOSWAVPCM16.extract(from: Data(contentsOf: fileURL))
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
}

@MainActor
final class IOSRealtimePCMStreamPlayer {
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
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        engine.prepare()
        try engine.start()
    }

    func enqueue(_ data: Data) {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.int16ChannelData?[0] else { return }
        data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            memcpy(channel, source, Int(frameCount) * MemoryLayout<Int16>.size)
        }
        buffer.frameLength = frameCount
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in self?.bufferDidFinish() }
        }
        if !player.isPlaying { player.play() }
    }

    func finish() async {
        streamEnded = true
        guard pendingBuffers > 0 else { return }
        await withCheckedContinuation { drainContinuation = $0 }
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
final class IOSRealtimeVoiceController {
    enum ComposerMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case voice = "Voice"
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case idle, recording, transcribing, waitingForHermes, speaking
    }

    var mode: ComposerMode = .text
    private(set) var phase: Phase = .idle
    private(set) var hasAPIKey = false
    var showsCredentialSheet = false
    var apiKeyDraft = ""
    private(set) var errorMessage: String?

    private let microphone = IOSRealtimeMicrophoneRecorder()
    private let player = IOSRealtimePCMStreamPlayer()
    private let client = IOSRealtimeClient()
    private var operationTask: Task<Void, Never>?
    private var awaitingHermesReply = false
    private var pendingSessionID: String?
    private var lastSpokenMessageID: Int?

    init() {
        hasAPIKey = (try? IOSRealtimeAPIKeyStore.load()) != nil
    }

    var statusTitle: String {
        switch phase {
        case .idle: return "Tap the microphone to speak"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .waitingForHermes: return "Hermes is responding…"
        case .speaking: return "Speaking Hermes's response…"
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
            try IOSRealtimeAPIKeyStore.save(apiKeyDraft)
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
            try IOSRealtimeAPIKeyStore.delete()
            hasAPIKey = false
            apiKeyDraft = ""
            showsCredentialSheet = false
            mode = .text
            resetVoiceTurn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleRecording(onTranscript: @escaping @MainActor (String) async -> Void) {
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
                    guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                        throw IOSRealtimeVoiceError.missingAPIKey
                    }
                    phase = .transcribing
                    let transcript = try await client.transcribe(apiKey: apiKey, pcm: pcm)
                    awaitingHermesReply = true
                    phase = .waitingForHermes
                    await onTranscript(transcript)
                } catch {
                    phase = .idle
                    errorMessage = error.localizedDescription
                }
            }
        default:
            break
        }
    }

    func noteHermesSend(sessionID: String?) {
        guard awaitingHermesReply else { return }
        pendingSessionID = sessionID
    }

    func handleSessionChange(to sessionID: String?) {
        if awaitingHermesReply {
            if pendingSessionID == nil {
                pendingSessionID = sessionID
            } else if pendingSessionID != sessionID {
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
              pendingSessionID == nil || pendingSessionID == sessionID,
              !trimmed.isEmpty,
              lastSpokenMessageID != messageID else { return }
        awaitingHermesReply = false
        pendingSessionID = nil
        lastSpokenMessageID = messageID
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                    throw IOSRealtimeVoiceError.missingAPIKey
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
        pendingSessionID = nil
        phase = .idle
        errorMessage = nil
    }

    private func enqueueAudio(_ data: Data) {
        guard phase == .speaking else { return }
        player.enqueue(data)
    }
}
