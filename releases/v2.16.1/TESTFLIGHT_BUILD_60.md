# Clawdia 2.16.1 TestFlight — build 60

## What to test

```text
Clawdia 2.16.1 build 60 — clearer launch and Voice feedback, with full iPhone loudspeaker playback.

- Launch Clawdia and confirm the connection experience fills the screen until the Hermes server is ready; tabs should appear only after connection succeeds.
- Start a Voice conversation and confirm the large microphone becomes a spinner under “Clawdia is thinking…” while the reply is preparing.
- Confirm the Voice waveform uses only light-to-dark Clawdia oranges while listening and speaking.
- With the route picker showing iPhone Speaker, confirm speech, Soft Lantern, and earcons come from the full bottom loudspeaker—not the quiet earpiece.
- Choose a Bluetooth, wired, or AirPlay output and confirm Clawdia continues respecting that explicit route.
- Complete several hands-free turns and confirm automatic listening resumes after every spoken reply, including through screen lock.

Known limitation: Push notifications remain disabled.
Report issues through TestFlight feedback.
```

## Upload

- [x] Voice release gate passes.
- [ ] Archive and upload build 60 using automatic Sycamore signing.
- [ ] Complete processing, export compliance, and `Anand Alone` assignment.
