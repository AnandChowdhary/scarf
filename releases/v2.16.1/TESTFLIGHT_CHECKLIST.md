# Clawdia 2.16.1 TestFlight — build 54

## Pre-flight

- [ ] `main` contains the complete Clawdia voice, Drive Mode, App Intents, naming, and icon changes.
- [ ] iOS build number is **54** with bundle identifier `so.sycamore.clawdia` and Sycamore team `UYNVFZ8S2F`.
- [ ] AppIcon master and all derived sizes use the supplied Clawdia portrait, with no alpha.
- [ ] `Scarf iOSTests`, simulator build, App Intents metadata extraction, and signed archive succeed.

## What to test

```text
Clawdia 2.16.1 build 54 — voice-first conversations and system shortcuts.

- Start Drive Mode, lock the phone, and continue a hands-free conversation.
- Confirm Clawdia listens again after speaking and submits only after you stop talking.
- Confirm listening, understood, working, speaking, paused, calls/Siri, and Bluetooth route changes have clear audio states.
- Try Siri/Shortcuts: “Start a conversation with Clawdia,” “Continue my last Clawdia session,” “Talk about the Sycamore project,” and “Capture an idea.”
- Adjust Clawdia’s voice, speed, and speaking style in Settings.
- Confirm the new pixel-art Clawdia portrait appears as the app icon.

Known limitation: Push notifications remain disabled.
Report issues through TestFlight feedback.
```

## Upload

- [ ] Archive `Clawdia iOS` for Any iOS Device using automatic signing.
- [ ] Export/upload through App Store Connect and wait for processing.
- [ ] Add build 54 to the existing tester group when processing completes.
