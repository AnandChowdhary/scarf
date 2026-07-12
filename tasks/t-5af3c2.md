---
id: t-5af3c2
title: Fix Clawdia voice failures and tab-bar overlap
status: done
added: 2026-07-12
---

## Description

The Drive Mode controls and voice error are obscured by the iOS floating tab bar on smaller phones, and the Realtime transcription session sends fields outside the current documented schema. Live testing also exposed lossy decimal serialization for the VAD threshold and an empty manual audio commit after Drive Mode's no-speech timeout. Repair the layout and Realtime lifecycle, then verify the voice screen against Hermes live.

## Plan

See `documents/plans/2026-07-12-fix-voice-screen-errors.md`.

## Artifacts

- `scarf/Scarf iOS/Chat/ChatView.swift`
- `scarf/Scarf iOS/Chat/IOSRealtimeVoiceService.swift`
- `scarf/Scarf iOSTests/Scarf_iOSTests.swift`

## Verification

- The voice composer is vertically scrollable, reserves floating-tab-bar clearance, and presents errors above the microphone.
- Audio-session priority and route failures now produce actionable messages instead of raw OSStatus codes.
- Realtime transcription uses `gpt-4o-mini-transcribe` without the undocumented `delay` field; generated speech remains on `gpt-realtime`.
- Realtime VAD serializes its threshold as exactly `0.35`, avoiding the API's maximum-decimal-places rejection.
- Drive Mode no longer commits a zero-length input buffer when automatic listening ends; manual commits require at least 100 ms of PCM audio.
- Live text against Hermes live returned the exact requested response in 2.0 seconds, and live voice reached listening, transcription, and Hermes handoff.
- A live 10-second no-speech Drive Mode run paused with Resume/End controls and no OpenAI error.
- `Scarf iOSTests`: 17 tests across 2 suites passed on the iOS 26.5 iPhone 17 Pro simulator.
- `git diff --check` passed.
