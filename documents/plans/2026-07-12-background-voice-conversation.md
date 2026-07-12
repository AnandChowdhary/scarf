# Background Voice Conversation

## Goal

Keep an active Clawdia voice conversation alive when the iPhone locks or the app backgrounds, while preserving the existing battery-friendly suspension behavior for ordinary text chat and inactive voice mode.

## Plan

1. Enable the iOS audio background mode and keep the ACP session alive only during an active voice turn.
2. Use one play-and-record audio-session configuration across listening, waiting tones, and spoken output so route/category changes do not interrupt the conversation.
3. Add distinct short cues for listening, understood, speaking, and paused; retain Soft Lantern as the working cue.
4. Keep automatic follow-up listening and end the background conversation after the existing no-speech timeout.
5. Add focused policy tests, run the iOS test target, then archive and upload TestFlight build 53.

## Constraints

- Do not keep text chats alive indefinitely in the background.
- Do not store credentials in source or release artifacts.
- Do not commit Memophant-owned plan, task, or wiki files with the application changes.
