# Dedicated Drive Mode Lifecycle

## Goal

Turn Clawdia's continuous voice conversation into an explicit Drive Mode that stays usable through screen lock, handles system audio ownership changes safely, and releases background audio after inactivity.

## Existing foundation

- The iOS target already declares the `audio` background mode.
- All microphone, waiting-tone, earcon, and speech players already use one `.playAndRecord` / `.voiceChat` category with speaker and Bluetooth HFP routing.
- Listening, understood, working, speaking, and paused earcons already exist.

## Implementation

1. Add an explicit Drive Mode activation state with prominent Start/End controls.
2. Keep the audio session and ACP transport alive through screen lock only while Drive Mode is active.
3. Observe audio interruptions, route changes, and media-services resets.
4. Pause on calls/Siri and Bluetooth loss; automatically resume when the system recommends it or a route returns, with a manual Resume fallback.
5. Keep the 10-second no-speech escape hatch, but end Drive Mode and deactivate audio after 10 minutes of idle time.
6. Add focused event-decoding, inactivity, and controller-state tests; run the iOS suite and simulator smoke build.

## Review safety

Background audio is tied to an explicit user-started audio experience, has an always-visible End control, emits clear recording/listening state, and automatically deactivates after extended inactivity. No silent audio is generated to keep the app alive.

Sources:

- [AVAudioSession playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)
- [Handling audio interruptions](https://developer.apple.com/documentation/AVFAudio/handling-audio-interruptions)
- [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- [App Review Guidelines 2.5.4](https://developer.apple.com/app-store/review/guidelines/)

