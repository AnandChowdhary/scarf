# Clawdia TestFlight Build 54

## Goal

Ship the accumulated Clawdia iOS work as version 2.16.1 build 54, using `Untitled-2.png` as the exact new app portrait/icon.

## Scope

1. Replace the 1024×1024 App Store icon master and every required derived icon size from the supplied 1078×1078 RGB, no-alpha source. Preserve the source artwork exactly; perform deterministic resizing only.
2. Include the pending voice streaming, continuous conversation, Drive Mode, background audio, earcons, Realtime voice settings, App Intents/App Shortcuts, and Clawdia user-facing language changes.
3. Increment only the iOS target build number from 53 to 54; retain marketing version 2.16.1 and bundle identifier `so.sycamore.clawdia`.
4. Run icon validation, the iOS test suite, an unsigned simulator build, and a signed generic-device archive.
5. Commit application code and release artifacts while leaving Memophant-owned task/plan/wiki changes unstaged, push `main`, export for App Store Connect, and upload build 54 to TestFlight.

## Verification

- Every AppIcon file has the pixel dimensions declared by `Contents.json`, is RGB, and has no alpha.
- `Scarf iOSTests` pass and App Intents metadata trains the Clawdia phrases.
- The archive validates as version 2.16.1 (54), team `UYNVFZ8S2F`, bundle `so.sycamore.clawdia`.
- App Store Connect accepts the upload for processing.
