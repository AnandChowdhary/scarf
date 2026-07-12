---
id: t-a8e4f1
title: Add a repeatable Clawdia voice end-to-end verification gate
status: done
added: 2026-07-12
---

## Description

Make the complete Clawdia voice round trip repeatable without requiring a person to speak: synthesize a deterministic utterance, feed its PCM through the app's Realtime transcription path, send the transcript through the configured Hermes server, observe streamed text and generated speech, and confirm continuous Voice returns to listening. Keep live API/server use opt-in while running fast protocol and audio-lifecycle checks by default.

## Plan

See `documents/plans/2026-07-12-clawdia-voice-e2e-gate.md`.

## Artifacts

- `scripts/verify-ios-voice-e2e.sh`
- `scarf/Scarf iOS/Chat/IOSRealtimeVoiceService.swift`
- `scarf/Scarf iOS/Chat/ChatView.swift`
- `scarf/Scarf iOSUITests/Scarf_iOSUITests.swift`
- `scarf/scarf.xcodeproj/xcshareddata/xcschemes/Clawdia Voice E2E.xcscheme`

## Verification

- `scripts/verify-ios-voice-e2e.sh` passes its 17-test hermetic suite on the iOS 26.5 iPhone 17 Pro simulator.
- The dedicated `Clawdia Voice E2E` scheme builds and targets the Clawdia host app correctly.
- A live run synthesized and paced 24 kHz PCM, reached OpenAI Realtime transcription, sent the transcript through Hermes live, observed the requested `VOICE E2E OK` response, entered speaking, returned to listening, and ended the Voice conversation cleanly.
- The live gate detects surfaced voice errors immediately and retries the isolated UI test once for transient socket setup failures.
- The post-response fixture is digital silence, preventing simulator playback from creating an accidental follow-up turn.
- Result bundles are saved under `build/voice-e2e/`.
- The Release configuration builds successfully for the iOS 26.5 simulator, proving the Debug-only fixture is absent from production compilation.
- Script syntax, shared-scheme XML, and `git diff --check` pass.
