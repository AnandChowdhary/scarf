# Clawdia 2.16.1 TestFlight — build 55

## Pre-flight

- [x] `main` contains the complete unified Voice mode, App Intents, naming, icon, and audio-reactive waveform changes.
- [x] iOS build number is **55** with bundle identifier `so.sycamore.clawdia` and Sycamore team `UYNVFZ8S2F`.
- [x] AppIcon master and all derived sizes use the supplied Clawdia portrait, with no alpha.
- [x] `Scarf iOSTests`, simulator build, App Intents metadata extraction, and signed archive succeed.

## What to test

```text
Clawdia 2.16.1 build 55 — natural voice conversations with audio-reactive visuals.

- Start a Voice conversation, lock the phone, and continue talking hands-free.
- Confirm Clawdia listens again after speaking and submits only after you stop talking.
- Confirm listening, understood, working, speaking, paused, calls/Siri, and Bluetooth route changes have clear audio states.
- Confirm the colorful waveform follows both your microphone input and Clawdia's spoken audio.
- Try Siri/Shortcuts: “Start a conversation with Clawdia,” “Continue my last Clawdia session,” “Talk about the Sycamore project,” and “Capture an idea.”
- Adjust Clawdia’s voice, speed, and speaking style in Settings.
- Confirm the new pixel-art Clawdia portrait appears as the app icon.

Known limitation: Push notifications remain disabled.
Report issues through TestFlight feedback.
```

## Upload

- [x] Archive `Clawdia iOS` for Any iOS Device using automatic signing.
- [x] Export/upload through App Store Connect and wait for processing.
- [ ] Add build 55 to the existing tester group when processing completes.

Build 55 finished processing at 1:19 PM on July 12, 2026. App Store Connect is waiting for the per-build App Encryption Documentation answer before the build can be added to `Anand Alone`.
