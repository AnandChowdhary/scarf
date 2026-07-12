//
//  Scarf_iOSTests.swift
//  Scarf iOSTests
//
//  Created by Alan Wizemann on 4/23/26.
//

import Foundation
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
}
