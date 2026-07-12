# Incremental Realtime Voice Streaming

## Goal

Begin speaking a Hermes reply while Hermes is still streaming, and make automatic follow-up listening end only after actual post-speech silence. Preserve the existing Hermes-owned conversation history.

Official Realtime API research confirmed that text input has no append/update buffer: `conversation.item.create` adds an atomic item and `response.create` starts a distinct inference. The supported implementation therefore keeps one WebSocket session open and sends new, nonduplicated text chunks as ordered speech responses. Microphone audio can be appended continuously and should use server turn detection.

## Plan

1. Feed nonduplicated assistant message deltas into the voice controller while generation is active.
2. Keep one Realtime speech WebSocket open and render ordered chunks without repeating the growing full message.
3. Stream microphone PCM to a Realtime session configured with server turn detection and transcription, while retaining a no-speech idle escape hatch.
4. Resume automatic listening only after the final spoken chunk is played; submit after Realtime reports post-speech silence.
5. Add focused protocol/state tests and run focused iOS tests plus a simulator build.

## Constraints

- Realtime remains an audio bridge; Hermes remains the sole reasoning and tool-using agent.
- Never speak text that has not appeared in the Hermes assistant message.
- Do not restart or overlap TTS connections for repeated SwiftUI observation updates.
- Do not treat the seven-second no-speech idle timeout as a maximum utterance duration.
- Existing uncommitted VAD and waiting-tone refinements must be preserved.

## Verification

- Clawdia iOS simulator build succeeded.
- Six focused iOS voice tests passed, covering server VAD configuration, the no-speech-only timeout, incremental nonduplicating speech chunks, final flushes, and out-of-band Realtime speech responses.
