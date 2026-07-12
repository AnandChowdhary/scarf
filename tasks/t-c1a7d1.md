---
id: t-c1a7d1
title: Rename user-facing Hermes language to Clawdia on iOS
status: done
added: 2026-07-12
---

## Description

Make Clawdia the only agent name shown to iOS users while retaining Hermes in internal identifiers, wire protocols, commands, paths, logs, and technically necessary runtime references.

## Plan

See `documents/plans/2026-07-12-clawdia-ios-language.md`.

## Artifacts

- `scarf/Scarf iOS/`
- `scarf/Scarf iOSTests/`
- `wiki/Chat.md`

## Verification

- Fresh `Clawdia iOS` simulator build succeeded without warnings.
- Fresh App Intents training generated “Continue my last Clawdia session…” and no user-facing Hermes shortcut phrase.
- `Scarf iOSTests` passed: 15 tests across 2 suites.
