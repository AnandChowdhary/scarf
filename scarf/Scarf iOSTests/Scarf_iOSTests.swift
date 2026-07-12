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
    @Test func automaticListeningTimesOutWhenNobodySpeaks() {
        var tracker = IOSVoiceActivityTracker(startedAt: 100)
        #expect(tracker.observe(level: 0.04, at: 106.9) == .keepListening)
        #expect(tracker.observe(level: 0.04, at: 107.0) == .timedOut)
    }

    @Test func automaticListeningFinishesAfterSpeechAndTrailingSilence() {
        var tracker = IOSVoiceActivityTracker(startedAt: 100)
        #expect(tracker.observe(level: 0.5, at: 101) == .keepListening)
        #expect(tracker.detectedSpeech)
        #expect(tracker.observe(level: 0.05, at: 102.0) == .keepListening)
        #expect(tracker.observe(level: 0.05, at: 102.2) == .finishUtterance)
    }

    @Test func automaticListeningExtendsWhileSpeechContinues() {
        var tracker = IOSVoiceActivityTracker(startedAt: 100)
        #expect(tracker.observe(level: 0.5, at: 101) == .keepListening)
        #expect(tracker.observe(level: 0.45, at: 102) == .keepListening)
        #expect(tracker.observe(level: 0.03, at: 103) == .keepListening)
        #expect(tracker.observe(level: 0.03, at: 103.2) == .finishUtterance)
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
}
