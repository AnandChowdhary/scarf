---
title: OpenAI Realtime Hermes Voice Bridge
type: note
tags:
- voice
- realtime
- hermes
- chat
created: 2026-07-11
updated: 2026-07-11
---

- [decision] Rich Chat voice mode is an audio bridge around the existing Hermes ACP session, not a second assistant conversation: Realtime transcription feeds the normal Hermes send path and only the persisted Hermes reply is spoken. #voice #architecture
- [decision] Microphone input uses a `gpt-realtime` WebSocket session with `gpt-realtime-whisper` under `audio.input.transcription`; spoken output uses `gpt-realtime` audio output. #openai #realtime
- [constraint] The user's bring-your-own OpenAI key is device-local in the macOS Keychain under service `com.scarf.openai-realtime`; it must never enter UserDefaults, repository files, logs, or errors. #security #keychain
- [gotcha] Standard-key WebSocket connections reject `type: transcription` session updates; the live-validated shape keeps `type: realtime` and nests the transcription model under `audio.input.transcription`. Wait for `session.updated` before sending audio. #wire-format

## Relations

- relates_to [[Hermes Integration]]
- relates_to [[Project-Scoped Chat and AGENTS.md Context]]
