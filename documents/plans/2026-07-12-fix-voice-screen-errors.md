# Fix voice screen errors and tab-bar overlap

## Goal

Make Clawdia's voice screen usable on smaller iPhones, keep Drive Mode and runtime errors above the floating tab bar, and make the OpenAI Realtime transcription and audio-buffer lifecycle valid in both manual and automatic listening.

## Changes

1. Put the tall voice surface in a bounded vertical scroll view and reserve clearance for the floating tab bar.
2. Move the voice error card above the microphone, with full wrapping and direct access to the API-key sheet.
3. Use `gpt-4o-mini-transcribe` for input transcription and remove the undocumented `delay` field; continue using `gpt-realtime` for generated speech.
4. Serialize VAD and voice-speed decimals without binary floating-point expansion.
5. Let server VAD own automatic-listening commits, and require at least 100 ms of captured PCM audio before any manual commit.
6. Add protocol/lifecycle regression coverage and run the iOS test suite plus a live Hermes simulator test.

## Verification

- Confirm the Realtime JSON has only documented transcription fields.
- Confirm the voice error remains visible above the microphone and the voice surface scrolls clear of the tab bar.
- Confirm a silent automatic-listening turn pauses Drive Mode instead of committing an empty buffer.
- Run `Scarf iOSTests` on an iOS Simulator and exercise the live Hermes connection.
