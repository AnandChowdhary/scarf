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
            return "Microphone access is off. Enable it for Clawdia in Settings → Privacy & Security → Microphone."
        case .recordingFailed:
            return "Clawdia couldn't start microphone recording."
        case .emptyRecording:
            return "No speech was recorded. Try again and speak after the mic turns red."
        case .malformedRecording:
            return "Clawdia couldn't read the recorded audio."
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
    private static let service = "so.sycamore.clawdia.openai-realtime"
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
            throw IOSRealtimeVoiceError.api("Clawdia couldn't read the OpenAI key from Keychain.")
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
            throw IOSRealtimeVoiceError.api("Clawdia couldn't update the OpenAI key in Keychain.")
        }
        var add = lookup
        add[kSecValueData] = Data(trimmed.utf8)
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw IOSRealtimeVoiceError.api("Clawdia couldn't save the OpenAI key in Keychain.")
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
            throw IOSRealtimeVoiceError.api("Clawdia couldn't remove the OpenAI key from Keychain.")
        }
    }
}

enum IOSRealtimeProtocol {
    typealias ServerEvent = (
        type: String,
        delta: String?,
        transcript: String?,
        errorMessage: String?
    )

    nonisolated static func decode(_ text: String) throws -> ServerEvent {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            throw IOSRealtimeVoiceError.invalidServerEvent
        }
        let error = object["error"] as? [String: Any]
        return (
            type: type,
            delta: object["delta"] as? String,
            transcript: object["transcript"] as? String,
            errorMessage: error?["message"] as? String
        )
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

nonisolated enum IOSPCM16Meter {
    static func level(in data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        var sumOfSquares = 0.0
        var sampleCount = 0
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: bytes.count - 1, by: 2) {
                let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                let sample = Double(Int16(bitPattern: bits)) / Double(Int16.max)
                sumOfSquares += sample * sample
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return 0 }
        let rms = sqrt(sumOfSquares / Double(sampleCount))
        return Float(min(1, sqrt(rms * 2.4)))
    }

    static func level(decibels: Float) -> Float {
        let floor: Float = -60
        guard decibels > floor else { return 0 }
        let linear = min(1, max(0, (decibels - floor) / -floor))
        return pow(linear, 1.45)
    }
}

nonisolated struct IOSVoiceActivityTracker {
    enum Decision: Equatable, Sendable {
        case keepListening
        case finishUtterance
        case timedOut
    }

    let startedAt: TimeInterval
    var speechThreshold: Float = 0.22
    var noSpeechTimeout: TimeInterval = 7
    var trailingSilence: TimeInterval = 1.15

    private(set) var detectedSpeech = false
    private var lastSpeechAt: TimeInterval?

    init(
        startedAt: TimeInterval,
        speechThreshold: Float = 0.22,
        noSpeechTimeout: TimeInterval = 7,
        trailingSilence: TimeInterval = 1.15
    ) {
        self.startedAt = startedAt
        self.speechThreshold = speechThreshold
        self.noSpeechTimeout = noSpeechTimeout
        self.trailingSilence = trailingSilence
    }

    mutating func observe(level: Float, at time: TimeInterval) -> Decision {
        if level >= speechThreshold {
            detectedSpeech = true
            lastSpeechAt = time
            return .keepListening
        }
        if !detectedSpeech, time - startedAt >= noSpeechTimeout {
            return .timedOut
        }
        if detectedSpeech,
           let lastSpeechAt,
           time - lastSpeechAt >= trailingSilence {
            return .finishUtterance
        }
        return .keepListening
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
                throw IOSRealtimeVoiceError.api(event.errorMessage ?? "OpenAI Realtime transcription failed.")
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
                throw IOSRealtimeVoiceError.api(event.errorMessage ?? "OpenAI Realtime speech failed.")
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
                throw IOSRealtimeVoiceError.api(event.errorMessage ?? "OpenAI Realtime connection failed.")
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
        let audioApplication = AVAudioApplication.shared
        let granted: Bool
        switch audioApplication.recordPermission {
        case .granted:
            granted = true
        case .denied:
            granted = false
        case .undetermined:
            granted = await AVAudioApplication.requestRecordPermission()
        @unknown default:
            granted = false
        }
        guard granted else { throw IOSRealtimeVoiceError.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
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
        newRecorder.isMeteringEnabled = true
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

    func currentLevel() -> Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return IOSPCM16Meter.level(decibels: recorder.averagePower(forChannel: 0))
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
final class IOSRealtimeWaitingSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private var loopTask: Task<Void, Never>?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        guard loopTask == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default)
        try session.setActive(true)
        engine.prepare()
        try engine.start()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                player.scheduleBuffer(
                    makeChimeBuffer(),
                    completionCallbackType: .dataPlayedBack
                ) { _ in }
                if !player.isPlaying { player.play() }
                try? await Task.sleep(for: .seconds(4.8))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        player.stop()
        engine.stop()
    }

    private func makeChimeBuffer() -> AVAudioPCMBuffer {
        let duration = 2.5
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return buffer }
        let notes: [(
            start: Double,
            duration: Double,
            frequency: Double,
            amplitude: Double,
            attack: Double,
            releasePower: Double,
            secondHarmonic: Double
        )] = [
            (0.00, 1.55, 329.63, 0.020, 0.24, 1.8, 0.08),
            (0.48, 1.65, 493.88, 0.016, 0.28, 1.9, 0.06),
            (0.96, 1.45, 659.25, 0.010, 0.30, 2.0, 0.04)
        ]
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            var value = 0.0
            for note in notes where time >= note.start && time <= note.start + note.duration {
                let localTime = time - note.start
                let progress = localTime / note.duration
                let attack = min(1, localTime / note.attack)
                let release = pow(max(0, 1 - progress), note.releasePower)
                let fundamental = sin(2 * .pi * note.frequency * localTime)
                let harmonic = sin(4 * .pi * note.frequency * localTime) * note.secondHarmonic
                value += (fundamental + harmonic) * attack * release * note.amplitude
            }
            samples[frame] = Float(value)
        }
        return buffer
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
        case idle, preparing, recording, transcribing, waitingForHermes, speaking
    }

    var mode: ComposerMode = .text
    private(set) var phase: Phase = .idle
    private(set) var hasAPIKey = false
    var showsCredentialSheet = false
    var apiKeyDraft = ""
    private(set) var errorMessage: String?
    private(set) var activityLevel: Float = 0
    private(set) var isAutomaticListening = false

    private let microphone = IOSRealtimeMicrophoneRecorder()
    private let player = IOSRealtimePCMStreamPlayer()
    private let waitingSound = IOSRealtimeWaitingSoundPlayer()
    private let client = IOSRealtimeClient()
    private var operationTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var awaitingHermesReply = false
    private var pendingSessionID: String?
    private var lastSpokenMessageID: Int?
    private var stopWhenRecordingStarts = false
    private var voiceActivityTracker: IOSVoiceActivityTracker?
    private var transcriptHandler: (@MainActor (String) async -> Void)?

    init() {
        hasAPIKey = (try? IOSRealtimeAPIKeyStore.load()) != nil
    }

    var statusTitle: String {
        switch phase {
        case .idle: return "Tap the microphone to speak"
        case .preparing: return "Starting the microphone…"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .waitingForHermes: return "Hermes is responding…"
        case .speaking: return "Speaking Hermes's response…"
        }
    }

    var statusSubtitle: String {
        switch phase {
        case .idle: return "Tap once for hands-free · hold to talk"
        case .preparing: return "Release after speaking when holding"
        case .recording where isAutomaticListening:
            return "Listening for your next question · stops after 7 seconds"
        case .recording: return "Tap again to send · or release if you're holding"
        case .transcribing: return "Turning your voice into a Hermes message"
        case .waitingForHermes: return "Your text response continues streaming above"
        case .speaking: return "Tap to stop · listening resumes when speech ends"
        }
    }

    var canRecord: Bool { phase == .idle || phase == .preparing || phase == .recording }

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

    func startRecording(
        automatic: Bool = false,
        onTranscript: @escaping @MainActor (String) async -> Void
    ) {
        guard mode == .voice else { return }
        guard phase == .idle else { return }
        errorMessage = nil
        transcriptHandler = onTranscript
        isAutomaticListening = automatic
        stopWhenRecordingStarts = false
        activityLevel = 0
        waitingSound.stop()
        operationTask?.cancel()
        phase = .preparing
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await microphone.start()
                guard !Task.isCancelled else {
                    microphone.cancel()
                    return
                }
                phase = .recording
                operationTask = nil
                startMetering(automatic: automatic)
                if stopWhenRecordingStarts {
                    stopWhenRecordingStarts = false
                    finishRecording()
                }
            } catch {
                phase = .idle
                isAutomaticListening = false
                operationTask = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func finishRecording() {
        if phase == .preparing {
            stopWhenRecordingStarts = true
            return
        }
        guard phase == .recording else { return }
        meterTask?.cancel()
        meterTask = nil
        voiceActivityTracker = nil
        isAutomaticListening = false
        activityLevel = 0
        phase = .transcribing
        let handler = transcriptHandler
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pcm = try microphone.stopAndReadPCM()
                guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                    throw IOSRealtimeVoiceError.missingAPIKey
                }
                let transcript = try await client.transcribe(apiKey: apiKey, pcm: pcm)
                awaitingHermesReply = true
                phase = .waitingForHermes
                try? waitingSound.start()
                operationTask = nil
                if let handler { await handler(transcript) }
            } catch is CancellationError {
                microphone.cancel()
                phase = .idle
                operationTask = nil
            } catch {
                microphone.cancel()
                phase = .idle
                operationTask = nil
                errorMessage = error.localizedDescription
            }
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
        } else if phase != .idle {
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
        waitingSound.stop()
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                    throw IOSRealtimeVoiceError.missingAPIKey
                }
                phase = .speaking
                activityLevel = 0.18
                try player.start()
                try await client.speak(apiKey: apiKey, text: trimmed) { [weak self] chunk in
                    await self?.enqueueAudio(chunk)
                }
                await player.finish()
                activityLevel = 0
                phase = .idle
                operationTask = nil
                try? await Task.sleep(for: .milliseconds(280))
                guard mode == .voice, phase == .idle, let transcriptHandler else { return }
                startRecording(automatic: true, onTranscript: transcriptHandler)
            } catch is CancellationError {
                player.stop()
                activityLevel = 0
                phase = .idle
                operationTask = nil
            } catch {
                player.stop()
                activityLevel = 0
                phase = .idle
                operationTask = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopSpeaking() {
        guard phase == .speaking else { return }
        operationTask?.cancel()
        player.stop()
        activityLevel = 0
        phase = .idle
        operationTask = nil
    }

    func resetVoiceTurn() {
        operationTask?.cancel()
        operationTask = nil
        meterTask?.cancel()
        meterTask = nil
        microphone.cancel()
        player.stop()
        waitingSound.stop()
        awaitingHermesReply = false
        pendingSessionID = nil
        stopWhenRecordingStarts = false
        voiceActivityTracker = nil
        isAutomaticListening = false
        activityLevel = 0
        phase = .idle
        errorMessage = nil
    }

    private func enqueueAudio(_ data: Data) {
        guard phase == .speaking else { return }
        let measured = IOSPCM16Meter.level(in: data)
        activityLevel = max(measured, activityLevel * 0.72)
        player.enqueue(data)
    }

    private func startMetering(automatic: Bool) {
        voiceActivityTracker = automatic
            ? IOSVoiceActivityTracker(startedAt: Date.timeIntervalSinceReferenceDate)
            : nil
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, phase == .recording else { return }
                let measured = microphone.currentLevel()
                activityLevel = max(measured, activityLevel * 0.78)
                if var tracker = voiceActivityTracker {
                    let decision = tracker.observe(
                        level: measured,
                        at: Date.timeIntervalSinceReferenceDate
                    )
                    voiceActivityTracker = tracker
                    switch decision {
                    case .keepListening:
                        break
                    case .finishUtterance:
                        finishRecording()
                        return
                    case .timedOut:
                        microphone.cancel()
                        voiceActivityTracker = nil
                        isAutomaticListening = false
                        activityLevel = 0
                        phase = .idle
                        meterTask = nil
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
