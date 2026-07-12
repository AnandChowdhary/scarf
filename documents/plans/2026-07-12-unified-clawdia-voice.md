# Unified Clawdia Voice

## Goal

Make Voice the only voice experience: one obvious microphone starts a natural continuous conversation, with no separate Drive Mode activation layer.

## Design

1. Remove the large Start Drive Mode banner and all Drive Mode wording from the Voice composer.
2. Make the first microphone press establish continuous voice-conversation ownership before recording. Tap remains hands-free; hold remains push-to-talk and submits on release.
3. Keep a compact End conversation control while active. Switching to Text, forgetting the API key, or ten minutes of paused inactivity also ends the conversation and releases audio/background ownership.
4. Preserve the existing `.playAndRecord` session, screen-lock behavior, continuous listening, earcons, call/Siri/Bluetooth interruption handling, and pause/resume behavior under voice-conversation terminology.
5. Update App Intent entry, E2E coverage, accessibility identifiers, unit-test names, and user documentation.

## Verification

- Completed: all 20 hermetic iOS tests through the Clawdia voice gate.
- Completed: live synthetic voice E2E against Realtime and the configured Hermes server, including automatic follow-up listening and clean conversation shutdown.
- Completed: Release simulator build and visual inspection of the live-test screenshot.
- Completed: obsolete-symbol scan, documentation refresh, scoped diff inspection, and `git diff --check`.
