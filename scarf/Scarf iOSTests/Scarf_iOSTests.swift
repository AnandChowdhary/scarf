//
//  Scarf_iOSTests.swift
//  Scarf iOSTests
//
//  Created by Alan Wizemann on 4/23/26.
//

@preconcurrency import AVFoundation
@preconcurrency import AVKit
import Foundation
import ScarfCore
import Testing
@testable import scarf_mobile

@Suite("Clawdia iOS")
struct Scarf_iOSTests {
    @MainActor
    @Test func voiceWaveformUsesOnlyOrderedClawdiaOrangeStops() {
        let fullPalette: [IOSVoiceWaveformPalette.Stop] = [
            .lightOrange,
            .midOrange,
            .deepOrange
        ]
        let brandedStops = Set(fullPalette)

        for phase in [
            IOSRealtimeVoiceController.Phase.recording,
            .speaking,
            .preparing,
            .transcribing,
            .waitingForHermes
        ] {
            let stops = IOSVoiceWaveformPalette.stops(for: phase)
            #expect(stops == fullPalette)
            #expect(Set(stops).isSubset(of: brandedStops))
        }

        #expect(IOSVoiceWaveformPalette.stops(for: .idle) == [.midOrange, .deepOrange])
        #expect(IOSVoiceWaveformPalette.stops(for: .paused) == [.midOrange, .deepOrange])
    }

    @MainActor
    @Test func voiceWaitingStateUsesOnePrimaryThinkingIndicator() {
        #expect(
            IOSRealtimeVoiceController.statusTitle(for: .waitingForHermes)
                == "Clawdia is thinking…"
        )
        #expect(
            IOSVoiceWorkingPresentation.showsLargeWorkingSpinner(for: .waitingForHermes)
        )
        #expect(!IOSVoiceWorkingPresentation.showsLargeWorkingSpinner(for: .transcribing))
        #expect(!IOSVoiceWorkingPresentation.showsLargeWorkingSpinner(for: .speaking))
        #expect(
            IOSVoiceWorkingPresentation.showsTranscriptThinking(
                isGenerating: true,
                mode: .text
            )
        )
        #expect(
            !IOSVoiceWorkingPresentation.showsTranscriptThinking(
                isGenerating: true,
                mode: .voice
            )
        )
    }

    @MainActor
    @Test func initialConnectionGateHidesApplicationUntilReady() {
        var gate = IOSInitialConnectionGate()

        #expect(gate.presentation(for: .idle) == .connecting)
        #expect(gate.presentation(for: .connecting) == .connecting)
        #expect(gate.presentation(for: .offline(reason: "No network")) == .connecting)
        #expect(gate.presentation(for: .reconnecting(attempt: 1, of: 3)) == .connecting)
        #expect(gate.presentation(for: .failed("No route")) == .failure("No route"))
        #expect(gate.presentation(for: .ready) == .application)

        gate.observe(.ready)

        #expect(gate.presentation(for: .ready) == .application)
    }

    @MainActor
    @Test func initialConnectionGateNeverRehidesEstablishedApplication() {
        var gate = IOSInitialConnectionGate()
        gate.observe(.ready)

        #expect(gate.presentation(for: .connecting) == .application)
        #expect(gate.presentation(for: .reconnecting(attempt: 2, of: 3)) == .application)
        #expect(gate.presentation(for: .offline(reason: "Airplane mode")) == .application)
        #expect(gate.presentation(for: .failed("Connection dropped")) == .application)
    }

    @Test func pcmMeterDistinguishesSilenceFromSpeech() {
        let silence = Data(repeating: 0, count: 512)
        var loud = Data()
        for _ in 0..<256 { loud.append(contentsOf: [0xFF, 0x7F]) }
        #expect(IOSPCM16Meter.level(in: silence) == 0)
        #expect(IOSPCM16Meter.level(in: loud) > 0.9)
        #expect(IOSPCM16Meter.level(decibels: -60) == 0)
        #expect(IOSPCM16Meter.level(decibels: -12) > 0.6)
    }

    @Test func pcmEnvelopePreservesRecentAudioShape() {
        var shaped = Data(repeating: 0, count: 400)
        for _ in 0..<200 { shaped.append(contentsOf: [0xFF, 0x7F]) }

        let envelope = IOSPCM16Meter.envelope(in: shaped, bucketCount: 4)

        #expect(envelope.count == 4)
        #expect(envelope[0] == 0)
        #expect(envelope[1] == 0)
        #expect(envelope[2] > 0.9)
        #expect(envelope[3] > 0.9)
    }

    @Test func waveformHistoryIsBoundedAndKeepsNewestSamples() {
        let history = IOSVoiceWaveformHistory.appending(
            [0.1, 0.4, 0.8, 1.2],
            to: IOSVoiceWaveformHistory.silence
        )

        #expect(history.count == IOSVoiceWaveformHistory.capacity)
        #expect(Array(history.suffix(4)) == [0.1, 0.4, 0.8, 1.0])
    }

    @Test func audioSessionFailuresHaveActionableMessages() {
        #expect(IOSRealtimeVoiceError.audioSessionInUse.errorDescription?.contains("current call") == true)
        #expect(IOSRealtimeVoiceError.audioRouteUnavailable.errorDescription?.contains("Reconnect") == true)
    }

    @Test func automaticListeningTimeoutIsNotAnUtteranceLimit() {
        #expect(IOSAutomaticListeningPolicy.shouldStop(
            startedAt: 100,
            now: 110,
            serverDetectedSpeech: false
        ))
        #expect(!IOSAutomaticListeningPolicy.shouldStop(
            startedAt: 100,
            now: 1_000,
            serverDetectedSpeech: true
        ))
    }

    @Test func realtimeManualCommitRequiresOneHundredMillisecondsOfPCM() {
        #expect(!IOSRealtimeAudioBufferPolicy.shouldCommit(byteCount: 0))
        #expect(!IOSRealtimeAudioBufferPolicy.shouldCommit(byteCount: 4_799))
        #expect(IOSRealtimeAudioBufferPolicy.shouldCommit(byteCount: 4_800))
    }

    @Test func realtimeTranscriptionUsesServerSilenceDetectionWithoutAutoResponse() throws {
        let json = try IOSRealtimeProtocol.transcriptionSessionUpdate(usesServerVAD: true)
        let data = try #require(json.data(using: .utf8))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        let audio = try #require(session["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        let vad = try #require(input["turn_detection"] as? [String: Any])
        let transcription = try #require(input["transcription"] as? [String: Any])

        #expect(vad["type"] as? String == "server_vad")
        #expect(vad["threshold"] as? Double == 0.35)
        #expect(vad["silence_duration_ms"] as? Int == 2_000)
        #expect(vad["create_response"] as? Bool == false)
        #expect(vad["interrupt_response"] as? Bool == false)
        #expect((input["noise_reduction"] as? [String: Any])?["type"] as? String == "far_field")
        #expect(transcription["model"] as? String == "gpt-4o-mini-transcribe")
        #expect(transcription["delay"] == nil)
        #expect(json.contains("\"threshold\":0.35"))
        #expect(!json.contains("0.34999999999999998"))
    }

    @Test func streamingSpeechBufferNeverRepeatsGrowingHermesText() {
        var buffer = IOSStreamingSpeechBuffer()
        buffer.ingest("Hello there. More")
        #expect(buffer.takeChunk() == "Hello there.")

        buffer.ingest("Hello there. More detail arrives as Hermes keeps streaming")
        #expect(buffer.takeChunk(allowPhraseBoundary: true) == "More detail arrives as Hermes keeps")

        buffer.ingest("Hello there. More detail arrives as Hermes keeps streaming")
        #expect(buffer.takeChunk(force: true) == "streaming")
        #expect(buffer.takeChunk(force: true) == nil)
    }

    @Test func streamingSpeechBufferFlushesShortFinalReply() {
        var buffer = IOSStreamingSpeechBuffer()
        buffer.ingest("Absolutely")
        #expect(buffer.takeChunk() == nil)
        #expect(buffer.takeChunk(force: true) == "Absolutely")
    }

    @Test func speechRequestCarriesOnlyTheExactNewChunkWithoutInstructions() throws {
        let exactText = "  Only this new fragment.\nKeep its spacing.  "
        let request = try IOSRealtimeProtocol.speechRequest(
            apiKey: "test-key",
            text: exactText
        )
        let data = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(request.httpMethod == "POST")
        #expect(root["model"] as? String == "gpt-4o-mini-tts")
        #expect(root["input"] as? String == exactText)
        #expect(root["response_format"] as? String == "pcm")
        #expect(root["instructions"] == nil)
        #expect(!String(decoding: data, as: UTF8.self).contains("verbatim"))
        #expect(!String(decoding: data, as: UTF8.self).contains("speech renderer"))
    }

    @Test func speechRequestUsesConfiguredVoiceAndSpeed() throws {
        let preferences = IOSRealtimeVoicePreferences(
            voice: .cedar,
            speed: 1.1
        )
        let request = try IOSRealtimeProtocol.speechRequest(
            apiKey: "test-key",
            text: "Hello from Clawdia.",
            preferences: preferences
        )
        let data = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(root["voice"] as? String == "cedar")
        #expect(root["speed"] as? Double == 1.1)
        #expect(String(decoding: data, as: UTF8.self).contains("\"speed\":1.1"))
    }

    @Test func realtimeVoicePreviewUsesAStableSpokenSample() {
        let sample = IOSRealtimeVoicePreviewController.sampleText

        #expect(sample.contains("Clawdia"))
        #expect(sample.contains("voice"))
        #expect(sample.contains("pace"))
        #expect(sample.hasSuffix("."))
    }

    @Test func voicePreferencesValidatePersistedValues() throws {
        let suite = "Scarf_iOSTests.voice.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not-a-voice", forKey: IOSRealtimeVoicePreferences.voiceKey)
        defaults.set(4.0, forKey: IOSRealtimeVoicePreferences.speedKey)

        let preferences = IOSRealtimeVoicePreferences.load(defaults: defaults)

        #expect(preferences.voice == .marin)
        #expect(preferences.speed == IOSRealtimeVoicePreferences.maximumSpeed)
    }

    @Test func voiceConversationInactivityRequiresTenIdleMinutes() {
        let timeout = IOSVoiceConversationInactivityPolicy.shutdownInterval
        #expect(timeout == 600)
        #expect(!IOSVoiceConversationInactivityPolicy.shouldEnd(
            lastActivity: 100,
            now: 100 + timeout - 0.01
        ))
        #expect(IOSVoiceConversationInactivityPolicy.shouldEnd(
            lastActivity: 100,
            now: 100 + timeout
        ))
    }

    @Test func voiceConversationDecodesAudioInterruptionsAndRouteAvailability() {
        let began = IOSRealtimeAudioEventDecoder.interruption(userInfo: [
            AVAudioSessionInterruptionTypeKey:
                NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)
        ])
        let ended = IOSRealtimeAudioEventDecoder.interruption(userInfo: [
            AVAudioSessionInterruptionTypeKey:
                NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
            AVAudioSessionInterruptionOptionKey:
                NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        ])
        let unavailable = IOSRealtimeAudioEventDecoder.routeChange(userInfo: [
            AVAudioSessionRouteChangeReasonKey:
                NSNumber(value: AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue)
        ])
        let available = IOSRealtimeAudioEventDecoder.routeChange(userInfo: [
            AVAudioSessionRouteChangeReasonKey:
                NSNumber(value: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue)
        ])
        let categoryChanged = IOSRealtimeAudioEventDecoder.routeChange(userInfo: [
            AVAudioSessionRouteChangeReasonKey:
                NSNumber(value: AVAudioSession.RouteChangeReason.categoryChange.rawValue)
        ])

        #expect(began == .interruptionBegan)
        #expect(ended == .interruptionEnded(shouldResume: true))
        #expect(unavailable == .routeUnavailable)
        #expect(available == .routeAvailable)
        #expect(categoryChanged == .routeAvailable)
    }

    @Test func voiceAudioOverridesOnlyDeviceLocalRoutesToSpeaker() {
        #expect(IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.builtInReceiver]
        ))
        #expect(IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.builtInSpeaker]
        ))
        #expect(IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.builtInReceiver, .builtInSpeaker]
        ))
        #expect(!IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(outputPortTypes: []))
        #expect(!IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.bluetoothHFP]
        ))
        #expect(!IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.headphones]
        ))
        #expect(!IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.airPlay]
        ))
        #expect(!IOSRealtimeAudioRoutePolicy.shouldOverrideToSpeaker(
            outputPortTypes: [.builtInReceiver, .bluetoothHFP]
        ))
    }

    @Test func voiceAudioSessionUsesFullLevelSpeakerConfiguration() {
        #expect(IOSRealtimeAudioSessionConfiguration.category == .playAndRecord)
        #expect(IOSRealtimeAudioSessionConfiguration.mode == .default)
        #expect(IOSRealtimeAudioSessionConfiguration.options.contains(.defaultToSpeaker))
        #expect(IOSRealtimeAudioSessionConfiguration.options.contains(.allowBluetoothHFP))
    }

    @Test @MainActor func voiceRoutePickerUsesTheNativeAudioFirstConfiguration() {
        let routePicker = IOSAudioRoutePicker.makeRoutePickerView()

        #expect(routePicker.prioritizesVideoDevices == false)
        #expect(routePicker.accessibilityIdentifier == IOSAudioRoutePicker.accessibilityIdentifier)
        #expect(routePicker.accessibilityLabel == "Choose audio output")
        #expect(routePicker.accessibilityHint?.contains("Bluetooth") == true)
    }

    @Test func appDeclaresAudioBackgroundMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("audio") == true)
    }

    @Test func systemEntryStorePersistsClearsAndExpiresRequests() throws {
        let suite = "Scarf_iOSTests.systemEntry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let createdAt = Date()
        let request = ClawdiaSystemEntryRequest(
            kind: .captureIdea,
            value: "  A safer voice-first commute  ",
            createdAt: createdAt
        )
        ClawdiaSystemEntryStore.save(request, defaults: defaults)

        #expect(
            ClawdiaSystemEntryStore.pendingRequest(
                defaults: defaults,
                now: createdAt.addingTimeInterval(1)
            ) == request
        )
        #expect(request.value == "A safer voice-first commute")

        ClawdiaSystemEntryStore.clear(id: UUID(), defaults: defaults)
        #expect(ClawdiaSystemEntryStore.pendingRequest(defaults: defaults, now: createdAt.addingTimeInterval(1)) != nil)

        ClawdiaSystemEntryStore.clear(id: request.id, defaults: defaults)
        #expect(ClawdiaSystemEntryStore.pendingRequest(defaults: defaults) == nil)

        ClawdiaSystemEntryStore.save(request, defaults: defaults)
        #expect(
            ClawdiaSystemEntryStore.pendingRequest(
                defaults: defaults,
                now: createdAt.addingTimeInterval(ClawdiaSystemEntryStore.maximumAge + 1)
            ) == nil
        )
    }

    @Test func projectIntentResolutionPrefersExactAndUniqueVisibleMatches() throws {
        let projects = [
            ProjectEntry(name: "Sycamore", path: "/work/sycamore"),
            ProjectEntry(name: "Sycamore Website", path: "/work/sycamore-web"),
            ProjectEntry(name: "Archived Lab", path: "/work/lab", archived: true)
        ]

        #expect(ClawdiaProjectResolver.resolve(named: "sycamore", in: projects)?.path == "/work/sycamore")
        #expect(ClawdiaProjectResolver.resolve(named: "website", in: projects)?.path == "/work/sycamore-web")
        #expect(ClawdiaProjectResolver.resolve(named: "sycamore", in: Array(projects.dropFirst()))?.path == "/work/sycamore-web")
        #expect(ClawdiaProjectResolver.resolve(named: "Archived Lab", in: projects) == nil)
    }

    @MainActor
    @Test func coordinatorRoutesAndTakesSystemEntryOnce() throws {
        let coordinator = ScarfGoCoordinator(serverID: ServerID())
        let request = ClawdiaSystemEntryRequest(kind: .continueLastSession)

        coordinator.receiveSystemEntry(request)

        #expect(coordinator.selectedTab == .text)
        #expect(coordinator.takeSystemEntry() == request)
        #expect(coordinator.takeSystemEntry() == nil)
    }

    @MainActor
    @Test func coordinatorRoutesHandsFreeSystemEntriesToVoice() throws {
        let coordinator = ScarfGoCoordinator(serverID: ServerID())

        coordinator.receiveSystemEntry(.init(kind: .startConversation))
        #expect(coordinator.selectedTab == .voice)

        coordinator.receiveSystemEntry(.init(kind: .projectConversation, value: "Sycamore"))
        #expect(coordinator.selectedTab == .voice)

        coordinator.receiveSystemEntry(.init(kind: .captureIdea, value: "Ship it"))
        #expect(coordinator.selectedTab == .text)
    }

    @MainActor
    @Test func rootModelAutomaticallyConnectsItsOnlyUsableServer() async throws {
        let serverID = ServerID()
        let config = IOSServerConfig(
            host: "only-server.example",
            user: "tester",
            displayName: "Only Server"
        )
        let key = SSHKeyBundle(
            privateKeyPEM: "test-private-key",
            publicKeyOpenSSH: "ssh-ed25519 test-public-key",
            comment: "test-only",
            createdAt: "2026-07-12T00:00:00Z"
        )
        let configStore = InMemoryIOSServerConfigStore()
        let keyStore = InMemorySSHKeyStore()
        try await configStore.save(config, id: serverID)
        try await keyStore.save(key, for: serverID)

        let model = RootModel(keyStore: keyStore, configStore: configStore)
        await model.load()

        guard case .connected(let selectedID, let selectedConfig, let selectedKey) = model.state else {
            Issue.record("Expected one usable server to connect automatically")
            return
        }
        #expect(selectedID == serverID)
        #expect(selectedConfig == config)
        #expect(selectedKey == key)
    }

    @MainActor
    @Test func rootModelKeepsMultipleServersInThePicker() async throws {
        let firstID = ServerID()
        let secondID = ServerID()
        let configStore = InMemoryIOSServerConfigStore()
        let keyStore = InMemorySSHKeyStore()
        let key = SSHKeyBundle(
            privateKeyPEM: "test-private-key",
            publicKeyOpenSSH: "ssh-ed25519 test-public-key",
            comment: "test-only",
            createdAt: "2026-07-12T00:00:00Z"
        )
        try await configStore.save(
            IOSServerConfig(host: "first.example", displayName: "First"),
            id: firstID
        )
        try await configStore.save(
            IOSServerConfig(host: "second.example", displayName: "Second"),
            id: secondID
        )
        try await keyStore.save(key, for: firstID)
        try await keyStore.save(key, for: secondID)

        let model = RootModel(keyStore: keyStore, configStore: configStore)
        await model.load()

        #expect(model.state == .serverList)
    }

    @MainActor
    @Test func rootModelKeepsAnIncompleteOnlyServerInThePicker() async throws {
        let serverID = ServerID()
        let configStore = InMemoryIOSServerConfigStore()
        try await configStore.save(
            IOSServerConfig(host: "missing-key.example", displayName: "Missing Key"),
            id: serverID
        )

        let model = RootModel(
            keyStore: InMemorySSHKeyStore(),
            configStore: configStore
        )
        await model.load()

        #expect(model.state == .serverList)
    }
}
