@preconcurrency import AVFoundation
import Foundation
import Observation
import os
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
    case audioSessionInUse
    case audioRouteUnavailable
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
        case .audioSessionInUse:
            return "iPhone audio is busy. End the current call, Siri session, or other recording app, then try again."
        case .audioRouteUnavailable:
            return "No microphone or audio output is currently available. Reconnect your audio device, then try again."
        case .api(let message):
            return "OpenAI Realtime: \(message)"
        }
    }
}

enum IOSRealtimeVoice: String, CaseIterable, Identifiable, Sendable {
    case alloy, ash, ballad, coral, echo, sage, shimmer, verse, marin, cedar

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var isRecommended: Bool { self == .marin || self == .cedar }
}

enum IOSRealtimeSpeakingStyle: String, CaseIterable, Identifiable, Sendable {
    case natural, warm, upbeat, calm, professional, animated

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var instruction: String {
        switch self {
        case .natural:
            return ""
        case .warm:
            return "Speak in a warm, empathetic, conversational tone."
        case .upbeat:
            return "Speak with upbeat, friendly energy."
        case .calm:
            return "Speak calmly, gently, and reassuringly."
        case .professional:
            return "Speak in a clear, polished, professional tone."
        case .animated:
            return "Speak expressively with lively, natural variation."
        }
    }
}

struct IOSRealtimeVoicePreferences: Equatable, Sendable {
    static let voiceKey = "so.sycamore.clawdia.realtime-voice.voice"
    static let speedKey = "so.sycamore.clawdia.realtime-voice.speed"
    static let styleKey = "so.sycamore.clawdia.realtime-voice.style"
    static let customInstructionsKey = "so.sycamore.clawdia.realtime-voice.custom-instructions"
    static let minimumSpeed = 0.25
    static let maximumSpeed = 1.5
    static let defaultValue = IOSRealtimeVoicePreferences()

    let voice: IOSRealtimeVoice
    let speed: Double
    let style: IOSRealtimeSpeakingStyle
    let customInstructions: String

    init(
        voice: IOSRealtimeVoice = .marin,
        speed: Double = 1,
        style: IOSRealtimeSpeakingStyle = .natural,
        customInstructions: String = ""
    ) {
        self.voice = voice
        let finiteSpeed = speed.isFinite ? speed : 1
        self.speed = min(Self.maximumSpeed, max(Self.minimumSpeed, finiteSpeed))
        self.style = style
        let trimmed = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customInstructions = String(trimmed.prefix(500))
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        let voice = defaults.string(forKey: voiceKey)
            .flatMap(IOSRealtimeVoice.init(rawValue:)) ?? .marin
        let style = defaults.string(forKey: styleKey)
            .flatMap(IOSRealtimeSpeakingStyle.init(rawValue:)) ?? .natural
        let speed = defaults.object(forKey: speedKey) == nil ? 1 : defaults.double(forKey: speedKey)
        return Self(
            voice: voice,
            speed: speed,
            style: style,
            customInstructions: defaults.string(forKey: customInstructionsKey) ?? ""
        )
    }

    var deliveryInstructions: String {
        [style.instruction, customInstructions]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var rendererInstructions: String {
        let fidelity = "Act only as a speech renderer. Read the supplied text aloud verbatim. Do not answer it, acknowledge it, summarize it, or add any words."
        guard !deliveryInstructions.isEmpty else { return fidelity }
        return "\(fidelity) Delivery guidance: \(deliveryInstructions)"
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

    static func transcriptionSessionUpdate(usesServerVAD: Bool = false) throws -> String {
        let turnDetection: Any = usesServerVAD
            ? [
                "type": "server_vad",
                // JSONSerialization expands some Swift Doubles (notably
                // 0.35) to 17 decimal places. Realtime rejects threshold
                // values with more than 16, so preserve the intended decimal.
                "threshold": NSDecimalNumber(string: "0.35"),
                "prefix_padding_ms": 500,
                "silence_duration_ms": 2_000,
                "create_response": false,
                "interrupt_response": false
            ] as [String: Any]
            : NSNull()
        return try encode([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": "gpt-realtime",
                "output_modalities": ["text"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": ["model": "gpt-4o-mini-transcribe"],
                        "noise_reduction": ["type": "far_field"],
                        "turn_detection": turnDetection
                    ]
                ]
            ]
        ])
    }

    static func speechSessionUpdate(
        preferences: IOSRealtimeVoicePreferences = .defaultValue
    ) throws -> String {
        try encode([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": "gpt-realtime",
                "output_modalities": ["audio"],
                "instructions": preferences.rendererInstructions,
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "turn_detection": NSNull()
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "voice": preferences.voice.rawValue,
                        "speed": decimalNumber(preferences.speed, fractionDigits: 2)
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

    /// Creates an out-of-band speech-rendering response. Reusing one Realtime
    /// session avoids a WebSocket handshake for every Hermes text chunk, while
    /// `conversation: none` prevents those renderer-only chunks from building a
    /// second assistant conversation alongside Hermes.
    static func createAudioResponse(
        for text: String,
        preferences: IOSRealtimeVoicePreferences = .defaultValue
    ) throws -> String {
        try encode([
            "type": "response.create",
            "response": [
                "conversation": "none",
                "output_modalities": ["audio"],
                "instructions": preferences.rendererInstructions,
                "input": [[
                    "type": "message",
                    "role": "user",
                    "content": [[
                        "type": "input_text",
                        "text": text
                    ]]
                ]]
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

    private static func decimalNumber(
        _ value: Double,
        fractionDigits: Int
    ) -> NSDecimalNumber {
        let format = "%.\(fractionDigits)f"
        return NSDecimalNumber(
            string: String(
                format: format,
                locale: Locale(identifier: "en_US_POSIX"),
                value
            )
        )
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
        return normalizedLevel(rms: rms)
    }

    /// Downsamples a PCM16 chunk into a small RMS envelope suitable for a
    /// real-time UI. This preserves the shape within the chunk instead of
    /// collapsing all audio into the controller's single scalar meter.
    static func envelope(in data: Data, bucketCount requestedBucketCount: Int) -> [Float] {
        let sampleCount = data.count / 2
        guard sampleCount > 0, requestedBucketCount > 0 else { return [] }
        let bucketCount = min(requestedBucketCount, sampleCount)
        var sums = Array(repeating: 0.0, count: bucketCount)
        var counts = Array(repeating: 0, count: bucketCount)

        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for sampleIndex in 0..<sampleCount {
                let offset = sampleIndex * 2
                let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                let sample = Double(Int16(bitPattern: bits)) / Double(Int16.max)
                let bucket = min(bucketCount - 1, sampleIndex * bucketCount / sampleCount)
                sums[bucket] += sample * sample
                counts[bucket] += 1
            }
        }

        return zip(sums, counts).map { sum, count in
            guard count > 0 else { return 0 }
            return normalizedLevel(rms: sqrt(sum / Double(count)))
        }
    }

    static func level(decibels: Float) -> Float {
        let floor: Float = -60
        guard decibels > floor else { return 0 }
        let linear = min(1, max(0, (decibels - floor) / -floor))
        return pow(linear, 1.45)
    }

    private static func normalizedLevel(rms: Double) -> Float {
        Float(min(1, sqrt(rms * 2.4)))
    }
}

nonisolated enum IOSVoiceWaveformHistory {
    static let capacity = 64
    static var silence: [Float] { Array(repeating: 0, count: capacity) }

    static func appending(_ levels: [Float], to history: [Float]) -> [Float] {
        let clamped = levels.map { min(1, max(0, $0)) }
        let combined = history + clamped
        if combined.count >= capacity {
            return Array(combined.suffix(capacity))
        }
        return Array(repeating: 0, count: capacity - combined.count) + combined
    }
}

nonisolated enum IOSAutomaticListeningPolicy {
    static let noSpeechTimeout: TimeInterval = 10

    static func shouldStop(
        startedAt: TimeInterval,
        now: TimeInterval,
        serverDetectedSpeech: Bool
    ) -> Bool {
        !serverDetectedSpeech && now - startedAt >= noSpeechTimeout
    }
}

nonisolated enum IOSRealtimeAudioBufferPolicy {
    /// Realtime rejects manual commits shorter than 100 ms. Input is mono
    /// PCM16 at 24 kHz: 24,000 samples × 2 bytes × 0.1 seconds.
    static let minimumCommitBytes = 4_800

    static func shouldCommit(byteCount: Int) -> Bool {
        byteCount >= minimumCommitBytes
    }
}

/// Turns an append-only Hermes message stream into nonduplicated speech input.
/// Realtime has no text equivalent of `input_audio_buffer.append`, so every
/// emitted chunk becomes one ordered out-of-band response on a persistent
/// speech session. Boundaries are adaptive: punctuation is preferred, long
/// text is capped, and a short debounce may release a multiword phrase.
nonisolated struct IOSStreamingSpeechBuffer {
    private(set) var fullText = ""
    private(set) var deliveredCharacterCount = 0

    var hasPendingText: Bool { deliveredCharacterCount < fullText.count }

    mutating func ingest(_ text: String) {
        fullText = text
        if deliveredCharacterCount > fullText.count {
            // Hermes streams append-only in normal operation. If a provider
            // revises/shrinks an already rendered prefix, audio cannot be
            // "unspoken"; skip over the surviving prefix without replaying it.
            deliveredCharacterCount = fullText.count
        }
    }

    mutating func takeChunk(force: Bool = false, allowPhraseBoundary: Bool = false) -> String? {
        guard hasPendingText else { return nil }
        let pending = String(fullText.dropFirst(deliveredCharacterCount))
        let consumedCount: Int
        if force {
            consumedCount = pending.count
        } else if let punctuationCount = Self.punctuationBoundary(in: pending) {
            consumedCount = punctuationCount
        } else if pending.count >= 120,
                  let wordCount = Self.wordBoundary(in: pending, limit: 180, minimum: 80) {
            consumedCount = wordCount
        } else if allowPhraseBoundary,
                  pending.split(whereSeparator: \Character.isWhitespace).count >= 6,
                  let wordCount = Self.wordBoundary(in: pending, limit: pending.count, minimum: 1) {
            consumedCount = wordCount
        } else {
            return nil
        }

        let raw = String(pending.prefix(consumedCount))
        deliveredCharacterCount += consumedCount
        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return spoken.isEmpty ? nil : spoken
    }

    private static func punctuationBoundary(in text: String) -> Int? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isNewline = character == "\n"
            let isTerminal = character == "." || character == "!" || character == "?"
            guard isNewline || isTerminal else {
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            while end < text.endIndex, "\"'”’)]}".contains(text[end]) {
                end = text.index(after: end)
            }
            let isStable = isNewline
                || character == "!"
                || character == "?"
                || (end < text.endIndex && text[end].isWhitespace)
            if isStable {
                while end < text.endIndex, text[end].isWhitespace {
                    end = text.index(after: end)
                }
                return text.distance(from: text.startIndex, to: end)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func wordBoundary(in text: String, limit: Int, minimum: Int) -> Int? {
        let capped = min(limit, text.count)
        guard capped >= minimum else { return nil }
        let prefix = String(text.prefix(capped))
        guard let boundary = prefix.lastIndex(where: \Character.isWhitespace) else { return nil }
        let count = prefix.distance(from: prefix.startIndex, to: prefix.index(after: boundary))
        return count >= minimum ? count : nil
    }
}

actor IOSRealtimeClient {
    func transcribe(
        apiKey: String,
        pcmStream: AsyncStream<Data>,
        commitOnStreamEnd: Bool,
        onSpeechStarted: @escaping @Sendable () async -> Void,
        onSpeechStopped: @escaping @Sendable () async -> Void
    ) async throws -> String {
        let connection = makeConnection(apiKey: apiKey)
        defer { connection.close() }
        try await wait(for: "session.created", socket: connection.socket)
        try await send(
            IOSRealtimeProtocol.transcriptionSessionUpdate(usesServerVAD: true),
            to: connection.socket
        )
        try await wait(for: "session.updated", socket: connection.socket)

        // Audio input and server events are full-duplex. The sender commits only
        // when the local stream is explicitly stopped (tap/hold-to-talk); in the
        // automatic path server VAD commits first and the task is cancelled when
        // the completed transcript arrives.
        let sender = Task { [weak self] in
            do {
                var appendedByteCount = 0
                for await chunk in pcmStream {
                    try Task.checkCancellation()
                    try await self?.send(IOSRealtimeProtocol.appendAudio(chunk), to: connection.socket)
                    appendedByteCount += chunk.count
                }
                try Task.checkCancellation()
                guard commitOnStreamEnd else {
                    // In automatic listening, server VAD owns the commit. A
                    // locally-ended stream means cancellation/no-speech; close
                    // to unblock receive without committing an empty new turn.
                    connection.close()
                    return
                }
                guard IOSRealtimeAudioBufferPolicy.shouldCommit(
                    byteCount: appendedByteCount
                ) else {
                    connection.close()
                    return
                }
                try await self?.send(IOSRealtimeProtocol.commitAudio(), to: connection.socket)
            } catch is CancellationError {
                return
            } catch {
                connection.close()
            }
        }
        defer { sender.cancel() }

        var transcript = ""
        while true {
            let event = try await receive(from: connection.socket)
            switch event.type {
            case "input_audio_buffer.speech_started":
                await onSpeechStarted()
            case "input_audio_buffer.speech_stopped":
                await onSpeechStopped()
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
        textStream: AsyncStream<String>,
        preferences: IOSRealtimeVoicePreferences,
        onAudioChunk: @escaping @Sendable (Data) async -> Void
    ) async throws {
        let connection = makeConnection(apiKey: apiKey)
        defer { connection.close() }
        try await wait(for: "session.created", socket: connection.socket)
        try await send(
            IOSRealtimeProtocol.speechSessionUpdate(preferences: preferences),
            to: connection.socket
        )
        try await wait(for: "session.updated", socket: connection.socket)

        for await text in textStream {
            try Task.checkCancellation()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            try await send(
                IOSRealtimeProtocol.createAudioResponse(for: trimmed, preferences: preferences),
                to: connection.socket
            )
            while true {
                let event = try await receive(from: connection.socket)
                switch event.type {
                case "response.output_audio.delta":
                    if let encoded = event.delta, let chunk = Data(base64Encoded: encoded) {
                        await onAudioChunk(chunk)
                    }
                case "response.done":
                    break
                case "error":
                    throw IOSRealtimeVoiceError.api(event.errorMessage ?? "OpenAI Realtime speech failed.")
                default:
                    continue
                }
                if event.type == "response.done" { break }
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
enum IOSRealtimeAudioSession {
    private static var continuousVoiceHoldsSession = false

    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
        } catch {
            let code = (error as NSError).code
            switch code {
            case AVAudioSession.ErrorCode.insufficientPriority.rawValue,
                 AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue:
                throw IOSRealtimeVoiceError.audioSessionInUse
            case AVAudioSession.ErrorCode.resourceNotAvailable.rawValue:
                throw IOSRealtimeVoiceError.audioRouteUnavailable
            default:
                throw error
            }
        }
    }

    static func beginContinuousVoice() throws {
        try activate()
        continuousVoiceHoldsSession = true
    }

    static func deactivate() {
        guard !continuousVoiceHoldsSession else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    static func endContinuousVoice() {
        continuousVoiceHoldsSession = false
        deactivate()
    }
}

nonisolated enum IOSRealtimeAudioLifecycleEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case outputDisconnected(wasBluetooth: Bool)
    case routeAvailable
    case routeUnavailable
    case mediaServicesLost
    case mediaServicesReset
}

nonisolated enum IOSRealtimeAudioEventDecoder {
    static func interruption(userInfo: [AnyHashable: Any]?) -> IOSRealtimeAudioLifecycleEvent? {
        guard let rawValue = (userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let optionValue = (userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    static func routeChange(userInfo: [AnyHashable: Any]?) -> IOSRealtimeAudioLifecycleEvent? {
        guard let rawValue = (userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue) else { return nil }
        switch reason {
        case .oldDeviceUnavailable:
            let previousRoute = userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription
            let bluetoothTypes: Set<AVAudioSession.Port> = [
                .bluetoothHFP, .bluetoothA2DP, .bluetoothLE
            ]
            let wasBluetooth = previousRoute?.outputs.contains {
                bluetoothTypes.contains($0.portType)
            } ?? false
            return .outputDisconnected(wasBluetooth: wasBluetooth)
        case .newDeviceAvailable, .wakeFromSleep, .routeConfigurationChange:
            return .routeAvailable
        case .noSuitableRouteForCategory:
            return .routeUnavailable
        case .unknown, .categoryChange, .override:
            return nil
        @unknown default:
            return nil
        }
    }
}

@MainActor
final class IOSRealtimeAudioSessionMonitor: NSObject {
    private let handler: @MainActor (IOSRealtimeAudioLifecycleEvent) -> Void
    private var isMonitoring = false

    init(handler: @escaping @MainActor (IOSRealtimeAudioLifecycleEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesLost(_:)),
            name: AVAudioSession.mediaServicesWereLostNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    func stop() {
        guard isMonitoring else { return }
        NotificationCenter.default.removeObserver(self)
        isMonitoring = false
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let event = IOSRealtimeAudioEventDecoder.interruption(
            userInfo: notification.userInfo
        ) else { return }
        handler(event)
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let event = IOSRealtimeAudioEventDecoder.routeChange(
            userInfo: notification.userInfo
        ) else { return }
        handler(event)
    }

    @objc private func handleMediaServicesLost(_ notification: Notification) {
        handler(.mediaServicesLost)
    }

    @objc private func handleMediaServicesReset(_ notification: Notification) {
        handler(.mediaServicesReset)
    }
}

nonisolated enum IOSVoiceConversationInactivityPolicy {
    static let shutdownInterval: TimeInterval = 10 * 60

    static func shouldEnd(lastActivity: TimeInterval, now: TimeInterval) -> Bool {
        now - lastActivity >= shutdownInterval
    }
}

@MainActor
final class IOSRealtimeMicrophoneRecorder {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<Data>.Continuation?
    private var tapInstalled = false
    private var level: Float = 0
    private var capturedByteCount = 0
    private var waveformSamples = IOSVoiceWaveformHistory.silence
    #if DEBUG
    private var syntheticFixtureConsumed = false
    private var syntheticFixtureTask: Task<Void, Never>?
    private var syntheticSpeechSynthesizer: AVSpeechSynthesizer?
    #endif

    func start() async throws -> AsyncStream<Data> {
        #if DEBUG
        if let phrase = ProcessInfo.processInfo.environment["CLAWDIA_VOICE_E2E_PHRASE"],
           !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !syntheticFixtureConsumed {
            syntheticFixtureConsumed = true
            try IOSRealtimeAudioSession.activate()
            stop()
            capturedByteCount = 0
            waveformSamples = IOSVoiceWaveformHistory.silence
            return syntheticSpeechStream(for: phrase)
        }
        if syntheticFixtureConsumed,
           ProcessInfo.processInfo.environment["CLAWDIA_VOICE_E2E_SILENT_FOLLOWUP"] == "1" {
            try IOSRealtimeAudioSession.activate()
            stop()
            capturedByteCount = 0
            waveformSamples = IOSVoiceWaveformHistory.silence
            var silentContinuation: AsyncStream<Data>.Continuation?
            let stream = AsyncStream<Data> { silentContinuation = $0 }
            continuation = silentContinuation
            return stream
        }
        #endif

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
        try IOSRealtimeAudioSession.activate()

        stop()
        capturedByteCount = 0
        waveformSamples = IOSVoiceWaveformHistory.silence
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 24_000,
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw IOSRealtimeVoiceError.recordingFailed
        }

        var streamContinuation: AsyncStream<Data>.Continuation?
        let stream = AsyncStream<Data> { streamContinuation = $0 }
        continuation = streamContinuation
        level = 0
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let data = Self.convert(buffer, using: converter, outputFormat: outputFormat) else { return }
            let measured = IOSPCM16Meter.level(in: data)
            Task { @MainActor [weak self] in
                guard let self else { return }
                level = max(measured, level * 0.78)
                capturedByteCount += data.count
                waveformSamples = IOSVoiceWaveformHistory.appending(
                    IOSPCM16Meter.envelope(in: data, bucketCount: 6),
                    to: waveformSamples
                )
                continuation?.yield(data)
            }
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw IOSRealtimeVoiceError.recordingFailed
        }
        return stream
    }

    func currentLevel() -> Float {
        level
    }

    func currentWaveformSamples() -> [Float] {
        waveformSamples
    }

    func hasMinimumCommitAudio() -> Bool {
        IOSRealtimeAudioBufferPolicy.shouldCommit(byteCount: capturedByteCount)
    }

    func cancel() {
        stop()
    }

    func stop() {
        #if DEBUG
        syntheticFixtureTask?.cancel()
        syntheticFixtureTask = nil
        syntheticSpeechSynthesizer?.stopSpeaking(at: .immediate)
        syntheticSpeechSynthesizer = nil
        #endif
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        continuation?.finish()
        continuation = nil
        level = 0
    }

    #if DEBUG
    /// Deterministic end-to-end test seam. A UI test opts in with a launch
    /// environment variable; production builds never compile this path.
    /// Synthesized speech is converted to the same 24 kHz mono PCM16 stream as
    /// the microphone and paced in 100 ms chunks so Realtime server VAD sees a
    /// realistic utterance followed by enough silence to complete the turn.
    private func syntheticSpeechStream(for phrase: String) -> AsyncStream<Data> {
        var streamContinuation: AsyncStream<Data>.Continuation?
        let stream = AsyncStream<Data> { streamContinuation = $0 }
        continuation = streamContinuation
        level = 0

        syntheticFixtureTask = Task { [weak self] in
            guard let self else { return }
            let pcm = await synthesizePCM16(phrase)
            guard !Task.isCancelled, !pcm.isEmpty else {
                continuation?.finish()
                return
            }

            let chunkSize = 4_800 // 100 ms at 24 kHz mono PCM16.
            var offset = 0
            while offset < pcm.count, !Task.isCancelled {
                let end = min(offset + chunkSize, pcm.count)
                let chunk = pcm.subdata(in: offset..<end)
                capturedByteCount += chunk.count
                level = max(IOSPCM16Meter.level(in: chunk), level * 0.78)
                waveformSamples = IOSVoiceWaveformHistory.appending(
                    IOSPCM16Meter.envelope(in: chunk, bucketCount: 6),
                    to: waveformSamples
                )
                continuation?.yield(chunk)
                offset = end
                try? await Task.sleep(for: .milliseconds(100))
            }

            // The production session uses a 2 s server-VAD silence threshold.
            // Give the live gate a full extra network round-trip window so the
            // completed transcript arrives before the synthetic stream closes;
            // 2.4 s proved too narrow under transient Realtime latency.
            let silence = Data(count: chunkSize)
            for _ in 0..<40 where !Task.isCancelled {
                capturedByteCount += silence.count
                level *= 0.72
                waveformSamples = IOSVoiceWaveformHistory.appending(
                    IOSPCM16Meter.envelope(in: silence, bucketCount: 6),
                    to: waveformSamples
                )
                continuation?.yield(silence)
                try? await Task.sleep(for: .milliseconds(100))
            }
            continuation?.finish()
        }
        return stream
    }

    private func synthesizePCM16(_ phrase: String) async -> Data {
        await withCheckedContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            syntheticSpeechSynthesizer = synthesizer
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            var accumulated = Data()
            var converter: AVAudioConverter?
            var didResume = false
            synthesizer.write(utterance) { [weak self] buffer in
                guard !didResume else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    didResume = true
                    self?.syntheticSpeechSynthesizer = nil
                    continuation.resume(returning: Data())
                    return
                }
                guard pcmBuffer.frameLength > 0 else {
                    didResume = true
                    self?.syntheticSpeechSynthesizer = nil
                    continuation.resume(returning: accumulated)
                    return
                }
                guard let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: 24_000,
                    channels: 1,
                    interleaved: false
                ) else { return }
                if converter == nil {
                    converter = AVAudioConverter(from: pcmBuffer.format, to: outputFormat)
                }
                guard let converter,
                      let data = Self.convert(
                        pcmBuffer,
                        using: converter,
                        outputFormat: outputFormat
                      ) else { return }
                accumulated.append(data)
            }
        }
    }
    #endif

    nonisolated private static func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> Data? {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio) + 16)
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }
        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        guard conversionError == nil,
              status != .error,
              output.frameLength > 0,
              let samples = output.int16ChannelData?[0] else { return nil }
        return Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
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
        try IOSRealtimeAudioSession.activate()
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

/// Settings-only audition path for the current Realtime voice preferences.
/// It deliberately uses an out-of-band `response.create` through the same
/// renderer and PCM player as conversation speech, so the preview reflects
/// the actual voice, speed, style, and custom guidance without touching ACP.
@MainActor
@Observable
final class IOSRealtimeVoicePreviewController {
    enum State: Equatable {
        case idle
        case connecting
        case playing
    }

    static let sampleText = "Hi, I’m Clawdia. This is a preview of my voice, pace, and speaking style."

    private(set) var state: State = .idle
    private(set) var errorMessage: String?

    private let client = IOSRealtimeClient()
    private let player = IOSRealtimePCMStreamPlayer()
    private var operationTask: Task<Void, Never>?
    private var activePreviewID: UUID?

    var isActive: Bool { state != .idle }

    func toggle(preferences: IOSRealtimeVoicePreferences) {
        if isActive {
            stop()
        } else {
            start(preferences: preferences)
        }
    }

    func start(preferences: IOSRealtimeVoicePreferences) {
        stop()
        errorMessage = nil
        state = .connecting
        let previewID = UUID()
        activePreviewID = previewID

        let textStream = AsyncStream<String> { continuation in
            continuation.yield(Self.sampleText)
            continuation.finish()
        }

        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                    throw IOSRealtimeVoiceError.missingAPIKey
                }
                try player.start()
                try await client.speak(
                    apiKey: apiKey,
                    textStream: textStream,
                    preferences: preferences
                ) { [weak self] chunk in
                    await self?.enqueue(chunk, previewID: previewID)
                }
                await player.finish()
                finish(previewID: previewID)
            } catch is CancellationError {
                finish(previewID: previewID)
            } catch {
                fail(error, previewID: previewID)
            }
        }
    }

    func stop() {
        activePreviewID = nil
        operationTask?.cancel()
        operationTask = nil
        player.stop()
        state = .idle
        IOSRealtimeAudioSession.deactivate()
    }

    private func enqueue(_ chunk: Data, previewID: UUID) {
        guard activePreviewID == previewID else { return }
        state = .playing
        player.enqueue(chunk)
    }

    private func finish(previewID: UUID) {
        guard activePreviewID == previewID else { return }
        activePreviewID = nil
        operationTask = nil
        player.stop()
        state = .idle
        IOSRealtimeAudioSession.deactivate()
    }

    private func fail(_ error: Error, previewID: UUID) {
        guard activePreviewID == previewID else { return }
        errorMessage = error.localizedDescription
        finish(previewID: previewID)
    }
}

@MainActor
final class IOSRealtimeWaitingSoundPlayer {
    private static let logger = Logger(
        subsystem: "so.sycamore.clawdia",
        category: "RealtimeWaitingSound"
    )
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

    func start() {
        guard loopTask == nil else { return }
        do {
            try IOSRealtimeAudioSession.activate()
            engine.prepare()
            try engine.start()
        } catch {
            player.stop()
            engine.stop()
            Self.logger.error("Could not start waiting sound: \(error.localizedDescription, privacy: .public)")
            return
        }
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
            samples[frame] = Float(value * 1.55)
        }
        return buffer
    }
}

@MainActor
final class IOSRealtimeStateCuePlayer {
    enum Cue {
        case listening
        case understood
        case speaking
        case paused

        var frequencies: [Double] {
            switch self {
            case .listening: return [523.25, 659.25]
            case .understood: return [659.25, 783.99]
            case .speaking: return [440.00, 659.25, 880.00]
            case .paused: return [493.88, 369.99]
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private var stopTask: Task<Void, Never>?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ cue: Cue) {
        stop()
        do {
            try IOSRealtimeAudioSession.activate()
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(makeBuffer(for: cue))
            player.play()
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player.stop()
        engine.stop()
    }

    private func makeBuffer(for cue: Cue) -> AVAudioPCMBuffer {
        let noteDuration = 0.105
        let noteGap = 0.018
        let duration = Double(cue.frequencies.count) * noteDuration
            + Double(max(0, cue.frequencies.count - 1)) * noteGap
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return buffer }

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let stride = noteDuration + noteGap
            let noteIndex = min(cue.frequencies.count - 1, Int(time / stride))
            let localTime = time - Double(noteIndex) * stride
            guard localTime <= noteDuration else {
                samples[frame] = 0
                continue
            }
            let progress = localTime / noteDuration
            let attack = min(1, localTime / 0.012)
            let release = pow(max(0, 1 - progress), 1.8)
            let frequency = cue.frequencies[noteIndex]
            let fundamental = sin(2 * .pi * frequency * localTime)
            let harmonic = sin(4 * .pi * frequency * localTime) * 0.08
            samples[frame] = Float((fundamental + harmonic) * attack * release * 0.11)
        }
        return buffer
    }
}

enum IOSVoiceConversationPauseReason: Equatable, Sendable {
    case noSpeech
    case user
    case interruption
    case outputDisconnected(wasBluetooth: Bool)
    case routeUnavailable
    case mediaServices

    var message: String {
        switch self {
        case .noSpeech:
            return "No speech detected. Tap the microphone when you're ready."
        case .user:
            return "Conversation paused. Tap the microphone to keep talking."
        case .interruption:
            return "A call, Siri, or another app is using audio. Clawdia will resume when available."
        case .outputDisconnected(let wasBluetooth):
            return wasBluetooth
                ? "Bluetooth disconnected. Reconnect it or tap the microphone to use iPhone audio."
                : "The audio device disconnected. Tap the microphone to use the current route."
        case .routeUnavailable:
            return "No usable audio route is available. Connect an audio device, then tap the microphone."
        case .mediaServices:
            return "iOS restarted its audio system. Clawdia will reconnect when it is ready."
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
        case idle, preparing, recording, transcribing, waitingForHermes, speaking, paused
    }

    var mode: ComposerMode = .text
    private(set) var phase: Phase = .idle
    private(set) var hasAPIKey = false
    var showsCredentialSheet = false
    var apiKeyDraft = ""
    private(set) var errorMessage: String?
    private(set) var activityLevel: Float = 0
    private(set) var waveformSamples = IOSVoiceWaveformHistory.silence
    private(set) var isAutomaticListening = false
    private(set) var isConversationActive = false
    private(set) var conversationPauseReason: IOSVoiceConversationPauseReason?
    private(set) var conversationNotice: String?

    private let microphone = IOSRealtimeMicrophoneRecorder()
    private let player = IOSRealtimePCMStreamPlayer()
    private let waitingSound = IOSRealtimeWaitingSoundPlayer()
    private let stateCue = IOSRealtimeStateCuePlayer()
    private let client = IOSRealtimeClient()
    private var operationTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var speechFlushTask: Task<Void, Never>?
    private var awaitingHermesReply = false
    private var pendingSessionID: String?
    private var stopWhenRecordingStarts = false
    private var serverDetectedSpeech = false
    private var speechBuffer = IOSStreamingSpeechBuffer()
    private var speechContinuation: AsyncStream<String>.Continuation?
    private var transcriptHandler: (@MainActor (String) async -> Void)?
    private var pausedHermesReplyIsComplete = false
    private var conversationLastActivity = Date.timeIntervalSinceReferenceDate
    private var conversationInactivityTask: Task<Void, Never>?
    @ObservationIgnored
    private lazy var audioSessionMonitor = IOSRealtimeAudioSessionMonitor { [weak self] event in
        self?.handleAudioLifecycleEvent(event)
    }

    init() {
        hasAPIKey = (try? IOSRealtimeAPIKeyStore.load()) != nil
    }

    var statusTitle: String {
        switch phase {
        case .idle: return "Tap the microphone to start"
        case .preparing: return "Starting the microphone…"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .waitingForHermes: return "Clawdia is responding…"
        case .speaking: return "Clawdia is speaking…"
        case .paused: return "Voice conversation paused"
        }
    }

    var statusSubtitle: String {
        switch phase {
        case .idle: return "Tap once for hands-free · hold to talk"
        case .preparing: return "Release after speaking when holding"
        case .recording where isAutomaticListening && isConversationActive:
            return "Speak naturally · pauses after 10 seconds with no speech"
        case .recording where isAutomaticListening:
            return "Speak naturally · sends after you stop · closes after 10 seconds of no speech"
        case .recording: return "Tap again to send · or release if you're holding"
        case .transcribing: return "Turning your voice into a Clawdia message"
        case .waitingForHermes: return "Your text response continues streaming above"
        case .speaking: return "Tap to stop · listening resumes when speech ends"
        case .paused: return conversationPauseReason?.message ?? "Tap the microphone to resume"
        }
    }

    var canRecord: Bool { phase == .idle || phase == .preparing || phase == .recording }

    /// A microphone-started Voice conversation owns background audio until
    /// the user ends it, switches to Text, or the inactivity policy expires.
    var shouldContinueInBackground: Bool {
        isConversationActive
    }

    func selectMode(_ newMode: ComposerMode) {
        if newMode == .voice, !hasAPIKey {
            apiKeyDraft = ""
            showsCredentialSheet = true
            return
        }
        if newMode == .text {
            if isConversationActive {
                endConversation()
            } else {
                resetVoiceTurn()
            }
        }
        mode = newMode
    }

    func startConversation(
        pushToTalk: Bool = false,
        onTranscript: @escaping @MainActor (String) async -> Void
    ) {
        guard mode == .voice, hasAPIKey, !isConversationActive, phase == .idle else { return }
        do {
            try IOSRealtimeAudioSession.beginContinuousVoice()
            transcriptHandler = onTranscript
            isConversationActive = true
            conversationPauseReason = nil
            conversationNotice = nil
            pausedHermesReplyIsComplete = false
            audioSessionMonitor.start()
            markConversationActivity()
            startRecording(automatic: !pushToTalk, onTranscript: onTranscript)
        } catch {
            IOSRealtimeAudioSession.endContinuousVoice()
            errorMessage = "Clawdia couldn't start the voice conversation: \(error.localizedDescription)"
        }
    }

    func endConversation() {
        finishConversation(notice: "Voice conversation ended.")
    }

    func resumeConversation() {
        guard isConversationActive, phase == .paused else { return }
        do {
            try IOSRealtimeAudioSession.activate()
            markConversationActivity()
            conversationPauseReason = nil
            phase = .idle

            if speechBuffer.hasPendingText {
                while let chunk = speechBuffer.takeChunk() {
                    enqueueSpeechText(chunk)
                }
                if pausedHermesReplyIsComplete,
                   let finalChunk = speechBuffer.takeChunk(force: true) {
                    enqueueSpeechText(finalChunk)
                }
                if pausedHermesReplyIsComplete {
                    pausedHermesReplyIsComplete = false
                    speechContinuation?.finish()
                } else if speechContinuation == nil {
                    phase = .waitingForHermes
                    waitingSound.start()
                }
                return
            }

            if awaitingHermesReply {
                phase = .waitingForHermes
                waitingSound.start()
                return
            }

            guard let transcriptHandler else { return }
            startRecording(automatic: true, onTranscript: transcriptHandler)
        } catch {
            conversationPauseReason = .routeUnavailable
            phase = .paused
            errorMessage = "Clawdia couldn't resume audio: \(error.localizedDescription)"
            scheduleConversationInactivityShutdown()
        }
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
            if isConversationActive {
                finishConversation(notice: nil)
            } else {
                resetVoiceTurn()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func startRecording(
        automatic: Bool = false,
        onTranscript: @escaping @MainActor (String) async -> Void
    ) {
        guard mode == .voice else { return }
        guard phase == .idle else { return }
        errorMessage = nil
        conversationNotice = nil
        transcriptHandler = onTranscript
        markConversationActivity()
        isAutomaticListening = automatic
        stopWhenRecordingStarts = false
        serverDetectedSpeech = false
        activityLevel = 0
        waveformSamples = IOSVoiceWaveformHistory.silence
        waitingSound.stop()
        operationTask?.cancel()
        phase = .preparing
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                    throw IOSRealtimeVoiceError.missingAPIKey
                }
                let pcmStream = try await microphone.start()
                guard !Task.isCancelled else {
                    microphone.cancel()
                    return
                }
                phase = .recording
                stateCue.play(.listening)
                startMetering(automatic: automatic)
                if stopWhenRecordingStarts {
                    stopWhenRecordingStarts = false
                    finishRecording()
                }
                let transcript = try await client.transcribe(
                    apiKey: apiKey,
                    pcmStream: pcmStream,
                    commitOnStreamEnd: !automatic,
                    onSpeechStarted: {
                        await MainActor.run { self.serverDetectedSpeech = true }
                    },
                    onSpeechStopped: {
                        await MainActor.run {
                            guard self.phase == .recording else { return }
                            self.phase = .transcribing
                            self.isAutomaticListening = false
                        }
                    }
                )
                meterTask?.cancel()
                meterTask = nil
                microphone.stop()
                isAutomaticListening = false
                activityLevel = 0
                stateCue.play(.understood)
                waitingSound.start()
                speechBuffer = IOSStreamingSpeechBuffer()
                awaitingHermesReply = true
                phase = .waitingForHermes
                operationTask = nil
                if let transcriptHandler { await transcriptHandler(transcript) }
            } catch {
                let message = error.localizedDescription
                if Task.isCancelled || error is CancellationError {
                    microphone.cancel()
                    waitingSound.stop()
                    isAutomaticListening = false
                    operationTask = nil
                    if isConversationActive, conversationPauseReason != nil { return }
                    phase = .idle
                    return
                }
                meterTask?.cancel()
                meterTask = nil
                microphone.cancel()
                waitingSound.stop()
                phase = .idle
                isAutomaticListening = false
                operationTask = nil
                if isConversationActive {
                    finishConversation(notice: nil)
                }
                errorMessage = message
            }
        }
    }

    func finishRecording() {
        if phase == .preparing {
            stopWhenRecordingStarts = true
            return
        }
        guard phase == .recording else { return }
        guard microphone.hasMinimumCommitAudio() else {
            operationTask?.cancel()
            meterTask?.cancel()
            meterTask = nil
            microphone.cancel()
            isAutomaticListening = false
            activityLevel = 0
            if isConversationActive {
                conversationPauseReason = .noSpeech
                phase = .paused
                stateCue.play(.paused)
                scheduleConversationInactivityShutdown()
            } else {
                phase = .idle
                errorMessage = IOSRealtimeVoiceError.emptyRecording.localizedDescription
                deactivateAudioSessionAfterCue()
            }
            return
        }
        meterTask?.cancel()
        meterTask = nil
        isAutomaticListening = false
        activityLevel = 0
        phase = .transcribing
        // Ending the local PCM stream makes the sender commit the buffer. The
        // existing operation task stays alive to receive the final transcript.
        microphone.stop()
        waitingSound.start()
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

    func observeHermesReply(sessionID: String?, text: String, isComplete: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .voice,
              awaitingHermesReply,
              pendingSessionID == nil || pendingSessionID == sessionID,
              !trimmed.isEmpty else { return }

        speechBuffer.ingest(text)
        markConversationActivity()
        if isConversationActive, phase == .paused {
            if isComplete {
                awaitingHermesReply = false
                pendingSessionID = nil
                pausedHermesReplyIsComplete = true
            }
            scheduleConversationInactivityShutdown()
            return
        }
        while let chunk = speechBuffer.takeChunk() {
            enqueueSpeechText(chunk)
        }

        speechFlushTask?.cancel()
        if isComplete {
            if let chunk = speechBuffer.takeChunk(force: true) {
                enqueueSpeechText(chunk)
            }
            awaitingHermesReply = false
            pendingSessionID = nil
            speechContinuation?.finish()
        } else if speechBuffer.hasPendingText {
            speechFlushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self,
                      let chunk = speechBuffer.takeChunk(allowPhraseBoundary: true) else { return }
                enqueueSpeechText(chunk)
            }
        }
    }

    private func enqueueSpeechText(_ text: String) {
        if speechContinuation == nil { startSpeechStream() }
        speechContinuation?.yield(text)
    }

    private func startSpeechStream() {
        var continuation: AsyncStream<String>.Continuation?
        let textStream = AsyncStream<String> { continuation = $0 }
        guard let continuation else { return }
        speechContinuation = continuation
        let preferences = IOSRealtimeVoicePreferences.load()
        waitingSound.stop()
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try IOSRealtimeAPIKeyStore.load() else {
                    throw IOSRealtimeVoiceError.missingAPIKey
                }
                markConversationActivity()
                phase = .speaking
                activityLevel = 0.18
                waveformSamples = IOSVoiceWaveformHistory.silence
                stateCue.play(.speaking)
                try player.start()
                try await client.speak(
                    apiKey: apiKey,
                    textStream: textStream,
                    preferences: preferences
                ) { [weak self] chunk in
                    await self?.enqueueAudio(chunk)
                }
                await player.finish()
                speechContinuation = nil
                speechBuffer = IOSStreamingSpeechBuffer()
                activityLevel = 0
                phase = .idle
                operationTask = nil
                try? await Task.sleep(for: .milliseconds(280))
                guard mode == .voice, phase == .idle, let transcriptHandler else { return }
                startRecording(automatic: true, onTranscript: transcriptHandler)
            } catch is CancellationError {
                player.stop()
                speechContinuation = nil
                activityLevel = 0
                operationTask = nil
                if isConversationActive, conversationPauseReason != nil { return }
                phase = .idle
            } catch {
                player.stop()
                speechContinuation = nil
                awaitingHermesReply = false
                pendingSessionID = nil
                activityLevel = 0
                phase = .idle
                operationTask = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopSpeaking() {
        guard phase == .speaking else { return }
        speechContinuation?.finish()
        speechContinuation = nil
        speechFlushTask?.cancel()
        speechFlushTask = nil
        operationTask?.cancel()
        player.stop()
        stateCue.play(.paused)
        awaitingHermesReply = false
        pendingSessionID = nil
        speechBuffer = IOSStreamingSpeechBuffer()
        activityLevel = 0
        operationTask = nil
        if isConversationActive {
            conversationPauseReason = .user
            phase = .paused
            scheduleConversationInactivityShutdown()
        } else {
            phase = .idle
            deactivateAudioSessionAfterCue()
        }
    }

    func resetVoiceTurn() {
        if isConversationActive {
            stopConversationOwnership()
        }
        resetActiveTurnForConversationTransition()
        errorMessage = nil
    }

    private func resetActiveTurnForConversationTransition() {
        operationTask?.cancel()
        operationTask = nil
        meterTask?.cancel()
        meterTask = nil
        speechFlushTask?.cancel()
        speechFlushTask = nil
        speechContinuation?.finish()
        speechContinuation = nil
        microphone.cancel()
        player.stop()
        waitingSound.stop()
        stateCue.stop()
        awaitingHermesReply = false
        pendingSessionID = nil
        stopWhenRecordingStarts = false
        serverDetectedSpeech = false
        speechBuffer = IOSStreamingSpeechBuffer()
        pausedHermesReplyIsComplete = false
        isAutomaticListening = false
        activityLevel = 0
        waveformSamples = IOSVoiceWaveformHistory.silence
        phase = .idle
        IOSRealtimeAudioSession.deactivate()
    }

    private func enqueueAudio(_ data: Data) {
        guard phase == .speaking else { return }
        let measured = IOSPCM16Meter.level(in: data)
        activityLevel = max(measured, activityLevel * 0.72)
        waveformSamples = IOSVoiceWaveformHistory.appending(
            IOSPCM16Meter.envelope(in: data, bucketCount: 8),
            to: waveformSamples
        )
        player.enqueue(data)
    }

    private func startMetering(automatic: Bool) {
        let startedAt = Date.timeIntervalSinceReferenceDate
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, phase == .recording else { return }
                let measured = microphone.currentLevel()
                activityLevel = max(measured, activityLevel * 0.78)
                waveformSamples = microphone.currentWaveformSamples()
                let now = Date.timeIntervalSinceReferenceDate
                // The ten-second limit is only a no-speech escape hatch. Once
                // Realtime reports speech_started it can never end an utterance;
                // only the server's post-speech silence event can do that.
                if automatic, IOSAutomaticListeningPolicy.shouldStop(
                    startedAt: startedAt,
                    now: now,
                    serverDetectedSpeech: serverDetectedSpeech
                ) {
                    operationTask?.cancel()
                    microphone.cancel()
                    isAutomaticListening = false
                    activityLevel = 0
                    meterTask = nil
                    stateCue.play(.paused)
                    if isConversationActive {
                        conversationPauseReason = .noSpeech
                        phase = .paused
                        scheduleConversationInactivityShutdown()
                    } else {
                        phase = .idle
                        deactivateAudioSessionAfterCue()
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func deactivateAudioSessionAfterCue() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, phase == .idle, !isConversationActive else { return }
            IOSRealtimeAudioSession.deactivate()
        }
    }

    private func handleAudioLifecycleEvent(_ event: IOSRealtimeAudioLifecycleEvent) {
        guard isConversationActive else { return }
        switch event {
        case .interruptionBegan:
            pauseConversation(for: .interruption, playCue: false)
        case .interruptionEnded(let shouldResume):
            if shouldResume { resumeConversation() }
        case .outputDisconnected(let wasBluetooth):
            pauseConversation(for: .outputDisconnected(wasBluetooth: wasBluetooth))
        case .routeUnavailable:
            pauseConversation(for: .routeUnavailable)
        case .routeAvailable:
            switch conversationPauseReason {
            case .outputDisconnected, .routeUnavailable, .mediaServices:
                resumeConversation()
            default:
                break
            }
        case .mediaServicesLost:
            pauseConversation(for: .mediaServices, playCue: false)
        case .mediaServicesReset:
            resumeConversation()
        }
    }

    private func pauseConversation(
        for reason: IOSVoiceConversationPauseReason,
        playCue: Bool = true
    ) {
        guard isConversationActive else { return }
        conversationPauseReason = reason
        conversationLastActivity = Date.timeIntervalSinceReferenceDate
        operationTask?.cancel()
        operationTask = nil
        meterTask?.cancel()
        meterTask = nil
        speechFlushTask?.cancel()
        speechFlushTask = nil
        speechContinuation?.finish()
        speechContinuation = nil
        microphone.cancel()
        player.stop()
        waitingSound.stop()
        stateCue.stop()
        isAutomaticListening = false
        activityLevel = 0
        phase = .paused
        if playCue { stateCue.play(.paused) }
        scheduleConversationInactivityShutdown()
    }

    private func markConversationActivity() {
        guard isConversationActive else { return }
        conversationLastActivity = Date.timeIntervalSinceReferenceDate
        conversationInactivityTask?.cancel()
        conversationInactivityTask = nil
    }

    private func scheduleConversationInactivityShutdown() {
        guard isConversationActive else { return }
        conversationInactivityTask?.cancel()
        let lastActivity = conversationLastActivity
        conversationInactivityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(IOSVoiceConversationInactivityPolicy.shutdownInterval))
            guard !Task.isCancelled, let self, isConversationActive,
                  phase == .paused || phase == .idle,
                  IOSVoiceConversationInactivityPolicy.shouldEnd(
                    lastActivity: lastActivity,
                    now: Date.timeIntervalSinceReferenceDate
                  ) else { return }
            finishConversation(notice: "Voice conversation ended after 10 minutes of inactivity.")
        }
    }

    private func finishConversation(notice: String?) {
        guard isConversationActive else { return }
        stopConversationOwnership()
        resetActiveTurnForConversationTransition()
        conversationNotice = notice
    }

    private func stopConversationOwnership() {
        isConversationActive = false
        conversationPauseReason = nil
        conversationInactivityTask?.cancel()
        conversationInactivityTask = nil
        audioSessionMonitor.stop()
        IOSRealtimeAudioSession.endContinuousVoice()
    }
}
