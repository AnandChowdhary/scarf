# GPT Realtime Voice Chat

## Goal

Add a native macOS voice mode to the existing Hermes Rich Chat. The user can switch the composer between Text and Voice, record an utterance, send the resulting transcript through the normal Hermes ACP session, and hear the completed Hermes response spoken with OpenAI's `gpt-realtime` model.

## Scope

- Add an in-page Text / Voice composer toggle and a prominent microphone control in Voice mode.
- Keep the existing Hermes ACP transcript and session as the source of truth: Realtime transcribes voice input, Scarf sends that text through the existing `onSend` path, and the normal Hermes assistant message remains the only persisted reply.
- Store the user's OpenAI API key in the macOS Keychain and provide first-use setup and key removal from the composer.
- Record microphone input as 24 kHz mono PCM, use the dedicated `gpt-realtime-whisper` Realtime transcription session, and pass that transcript into Hermes.
- After the Hermes turn settles, send its final assistant text to `gpt-realtime` for streamed speech playback.
- Add microphone usage-copy coverage, deterministic protocol/parser tests, and a local build verification.

## Architecture

- `OpenAIRealtimeVoiceService` owns WebSocket session lifecycle, Realtime events, microphone recording, and audio playback. The SwiftUI view never calls the API directly.
- `OpenAIRealtimeAPIKeyStore` is the sole Keychain boundary. No credential is written to repository files, `UserDefaults`, logs, or error strings.
- `RealtimeVoiceController` bridges the Voice composer to the existing Hermes send callback and observes the completed assistant turn for spoken playback.
- Realtime event encoding/decoding and WAV PCM extraction are isolated into deterministic helpers for unit tests.

## Security and product constraints

- This fork is bring-your-own-key. The key is device-local in Keychain and sent only in the TLS WebSocket authorization header.
- The shipped application contains no OpenAI key.
- Realtime voice is opt-in and starts only after an explicit mic action and system microphone permission.
- Voice mode does not create a second model conversation or bypass Hermes; all agent reasoning, tools, permissions, and persistence continue through the existing ACP session.
- The existing terminal-mode Hermes voice controls remain unchanged.

## Verification

- Unit-test client event shapes, server transcript/error decoding, and WAV PCM extraction.
- Run focused tests and `./scripts/local-build.sh`.
- Inspect the final diff for secret leakage and unrelated managed-tier changes before committing only application code.
