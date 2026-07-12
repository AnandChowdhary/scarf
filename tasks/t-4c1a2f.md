---
id: t-4c1a2f
title: Add Clawdia system entry points with App Intents
status: done
added: 2026-07-12
---

## Description

Add App Intents and App Shortcuts for starting a Clawdia conversation, resuming the last Hermes session, talking about a named project, and capturing an idea. Invocations must survive cold launch and route into the existing iOS Chat implementation.

## Plan

See `documents/plans/2026-07-12-clawdia-app-intents.md`.

## Artifacts

- `scarf/Scarf iOS/App/ClawdiaAppIntents.swift`
- `scarf/Scarf iOS/App/ScarfIOSApp.swift`
- `scarf/Scarf iOS/App/ScarfGoCoordinator.swift`
- `scarf/Scarf iOS/App/ScarfGoTabRoot.swift`
- `scarf/Scarf iOS/Chat/ChatView.swift`
- `scarf/Scarf iOSTests/Scarf_iOSTests.swift`

## Verification

- `Clawdia iOS` simulator build succeeded, including App Intents metadata extraction and Siri phrase training.
- `Scarf iOSTests` passed: 15 tests across 2 suites.
