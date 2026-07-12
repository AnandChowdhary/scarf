# Clawdia voice end-to-end verification gate

## Goal

Provide one repeatable command that verifies Clawdia's voice lifecycle without asking a person to speak, while keeping API-consuming, server-mutating tests explicit and separate from the ordinary hermetic suite.

## Design

1. Add a Debug-only synthetic microphone fixture driven by a launch environment variable. It uses on-device speech synthesis, converts the buffers to the same 24 kHz mono PCM16 format as the microphone, and paces the chunks in real time.
2. Add stable accessibility identifiers for voice status and controls.
3. Replace the placeholder iOS UI test with an opt-in live voice round-trip: connect to the existing simulator server, select Voice, press the microphone, observe listening/transcribing/working/speaking, assert the requested Hermes response, and confirm automatic listening resumes.
4. Add the iOS UI-test target to the shared Clawdia scheme.
5. Add `scripts/verify-ios-voice-e2e.sh`: run the hermetic iOS tests by default and run the live UI round-trip with `--live` against a preconfigured simulator.
6. Document prerequisites, mutation/cost boundaries, and failure artifacts.

## Verification

- Completed: focused PCM threshold and Realtime payload tests.
- Completed: all 17 `Scarf iOSTests` on the iOS 26.5 iPhone 17 Pro simulator.
- Completed: live UI round trip against Hermes live, including return to listening and clean Voice-conversation shutdown.
- Completed: dedicated shared E2E scheme, shell syntax, and XML validation.
- Final diff and Release-build checks are recorded in the task verification.
