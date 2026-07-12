//
//  Scarf_iOSTests.swift
//  Scarf iOSTests
//
//  Created by Alan Wizemann on 4/23/26.
//

@preconcurrency import AVFoundation
import Foundation
import ScarfCore
import Testing
@testable import scarf_mobile

@Suite("Clawdia iOS")
struct Scarf_iOSTests {
    @Test func pcmMeterDistinguishesSilenceFromSpeech() {
        let silence = Data(repeating: 0, count: 512)
        var loud = Data()
        for _ in 0..<256 { loud.append(contentsOf: [0xFF, 0x7F]) }
        #expect(IOSPCM16Meter.level(in: silence) == 0)
        #expect(IOSPCM16Meter.level(in: loud) > 0.9)
        #expect(IOSPCM16Meter.level(decibels: -60) == 0)
        #expect(IOSPCM16Meter.level(decibels: -12) > 0.6)
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

    @Test func realtimeTranscriptionUsesServerSilenceDetectionWithoutAutoResponse() throws {
        let json = try IOSRealtimeProtocol.transcriptionSessionUpdate(usesServerVAD: true)
        let data = try #require(json.data(using: .utf8))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        let audio = try #require(session["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        let vad = try #require(input["turn_detection"] as? [String: Any])

        #expect(vad["type"] as? String == "server_vad")
        #expect(vad["silence_duration_ms"] as? Int == 2_000)
        #expect(vad["create_response"] as? Bool == false)
        #expect(vad["interrupt_response"] as? Bool == false)
        #expect((input["noise_reduction"] as? [String: Any])?["type"] as? String == "far_field")
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

    @Test func speechResponsesAreOutOfBandAndCarryOnlyTheNewChunk() throws {
        let json = try IOSRealtimeProtocol.createAudioResponse(for: "Only this new fragment")
        let data = try #require(json.data(using: .utf8))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let response = try #require(root["response"] as? [String: Any])
        let input = try #require(response["input"] as? [[String: Any]])
        let message = try #require(input.first)
        let content = try #require(message["content"] as? [[String: Any]])

        #expect(response["conversation"] as? String == "none")
        #expect(content.first?["text"] as? String == "Only this new fragment")
    }

    @Test func speechSessionUsesConfiguredVoiceSpeedAndStyle() throws {
        let preferences = IOSRealtimeVoicePreferences(
            voice: .cedar,
            speed: 1.25,
            style: .warm,
            customInstructions: "Use subtle dry humor."
        )
        let json = try IOSRealtimeProtocol.speechSessionUpdate(preferences: preferences)
        let data = try #require(json.data(using: .utf8))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        let audio = try #require(session["audio"] as? [String: Any])
        let output = try #require(audio["output"] as? [String: Any])
        let instructions = try #require(session["instructions"] as? String)

        #expect(output["voice"] as? String == "cedar")
        #expect(output["speed"] as? Double == 1.25)
        #expect(instructions.contains("warm, empathetic"))
        #expect(instructions.contains("subtle dry humor"))
        #expect(instructions.contains("verbatim"))
    }

    @Test func voicePreferencesValidatePersistedValues() throws {
        let suite = "Scarf_iOSTests.voice.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not-a-voice", forKey: IOSRealtimeVoicePreferences.voiceKey)
        defaults.set(4.0, forKey: IOSRealtimeVoicePreferences.speedKey)
        defaults.set(IOSRealtimeSpeakingStyle.calm.rawValue, forKey: IOSRealtimeVoicePreferences.styleKey)
        defaults.set("  Pause between key ideas.  ", forKey: IOSRealtimeVoicePreferences.customInstructionsKey)

        let preferences = IOSRealtimeVoicePreferences.load(defaults: defaults)

        #expect(preferences.voice == .marin)
        #expect(preferences.speed == IOSRealtimeVoicePreferences.maximumSpeed)
        #expect(preferences.style == .calm)
        #expect(preferences.customInstructions == "Pause between key ideas.")
    }

    @Test func driveModeInactivityRequiresTenIdleMinutes() {
        let timeout = IOSDriveModeInactivityPolicy.shutdownInterval
        #expect(timeout == 600)
        #expect(!IOSDriveModeInactivityPolicy.shouldEnd(
            lastActivity: 100,
            now: 100 + timeout - 0.01
        ))
        #expect(IOSDriveModeInactivityPolicy.shouldEnd(
            lastActivity: 100,
            now: 100 + timeout
        ))
    }

    @Test func driveModeDecodesAudioInterruptionsAndRouteAvailability() {
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

        #expect(began == .interruptionBegan)
        #expect(ended == .interruptionEnded(shouldResume: true))
        #expect(unavailable == .routeUnavailable)
        #expect(available == .routeAvailable)
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

        #expect(coordinator.selectedTab == .chat)
        #expect(coordinator.takeSystemEntry() == request)
        #expect(coordinator.takeSystemEntry() == nil)
    }
}
