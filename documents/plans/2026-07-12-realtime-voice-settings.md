# Realtime Voice Settings

## Goal

Let Clawdia users choose the OpenAI Realtime voice, playback speed, and speaking style from the existing iOS Settings screen.

## Research

- Realtime `audio.output.voice` supports `alloy`, `ash`, `ballad`, `coral`, `echo`, `sage`, `shimmer`, `verse`, `marin`, and `cedar`; OpenAI recommends `marin` and `cedar` for best quality.
- Realtime `audio.output.speed` accepts `0.25` through `1.5` and can change only between model turns.
- Tone, emotion, and delivery style are guided through `instructions`; these are guidance rather than guaranteed controls.
- A voice cannot change after a session has already emitted audio, so Clawdia applies preferences when it opens the next short-lived speech-rendering session.

Source: [OpenAI Realtime API reference](https://developers.openai.com/api/reference/resources/realtime)

## Implementation

1. Add validated, UserDefaults-backed Realtime voice preferences with `marin`, `1.0×`, and natural delivery as defaults.
2. Add a Clawdia Realtime Voice section to iOS Settings with voice, speed, style, custom guidance, and reset controls.
3. Pass the selected voice and speed in `session.update`, and combine style guidance with the verbatim speech-renderer instruction.
4. Add focused protocol/persistence tests and run the iOS test target.

