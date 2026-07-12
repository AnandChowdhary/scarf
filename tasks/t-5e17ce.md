---
id: t-5e17ce
title: Stream Hermes replies and use Realtime turn detection
status: done
added: 2026-07-12
completed: 2026-07-12
---

## Description

Keep one Realtime speech session open for incremental Hermes output, and replace the fragile local automatic-listening cutoff with live Realtime turn detection so a follow-up is submitted only after post-speech silence.

## Plan

See `documents/plans/2026-07-12-sentence-level-voice-streaming.md`.

## Artifacts

- `scarf/Scarf iOS/Chat/IOSRealtimeVoiceService.swift`
- `scarf/Scarf iOS/Chat/ChatView.swift`
- `scarf/Scarf iOSTests/Scarf_iOSTests.swift`
