# Clawdia 2.16.1 TestFlight — build 57

## What to test

```text
Clawdia 2.16.1 build 57 — voice audio now defaults to the iPhone loudspeaker.

- Start a Voice conversation without headphones and confirm listening cues, Soft Lantern waiting audio, and Clawdia's spoken responses use the full loudspeaker rather than the handset receiver.
- Open System → Settings → Realtime Voice and confirm Preview voice also uses the loudspeaker.
- Connect Bluetooth or wired headphones and confirm Clawdia preserves that output instead of forcing the phone speaker.
- Disconnect an external output and confirm the conversation pauses safely rather than changing routes unexpectedly.

Known limitation: Push notifications remain disabled.
Report issues through TestFlight feedback.
```

## Upload

- [x] Voice release gate passes.
- [x] Archive and upload build 57 using automatic Sycamore signing.
- [x] App Store Connect processing completed successfully.
- [ ] Submit export compliance and assign build 57 to `Anand Alone`.
