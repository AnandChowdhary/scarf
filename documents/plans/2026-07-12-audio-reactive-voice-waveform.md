# Audio-reactive Clawdia waveform

## Goal

Make the Voice visualization feel alive and truthful: its visible shape should follow the recent microphone or spoken-output signal rather than merely changing the amplitude of decorative lines.

## Design

1. Derive a small normalized RMS envelope from each PCM16 chunk and maintain a bounded rolling history for microphone and playback audio.
2. Publish that history through the Voice controller alongside the existing scalar meter.
3. Replace the multi-line sine renderer with a mirrored, smoothed, filled SwiftUI Canvas ribbon using Clawdia's orange/pink/cyan/purple palette, soft glow, and phase-specific styling.
4. Use actual envelope history while listening/speaking. Use a quiet deterministic breathing shape only for preparing, transcribing, and working states where there is no user/voice PCM to visualize.
5. Respect Reduce Motion by freezing non-audio ambient motion while continuing to show real signal changes.
6. Add focused envelope/history tests and update current Voice documentation.

## Verification

- [x] Hermetic Clawdia voice gate: 22 tests passed.
- [x] Live synthetic Realtime/Hermes voice round trip passed; listening and speaking PCM-driven screenshots were inspected.
- [x] Clawdia Release configuration built for the iOS simulator with code signing disabled.
- [x] `git diff --check` passed and the scoped diff was inspected.
