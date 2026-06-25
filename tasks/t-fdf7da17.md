---
id: t-fdf7da17
title: B1: wire selected profile into ServerContext; rebuild tab subtree on change
status: todo
added: 2026-06-25
priority: high
---

## Description

Parent: t-873f7df9 (#120 Design B). Makes all direct-file/DB iOS surfaces (dashboard, memory, cron, sessions, gateway_state, scarf/) follow the selected profile via the existing remoteHome→paths.home seam.

## Plan

## Plan
1. In ScarfGoTabRoot (and any other place building context from `config`), compute resolved remoteHome from B0 selection BEFORE `config.toServerContext(id:)`; inject into the SSHConfig/remoteHome.
2. Key the tab subtree on the selected profile (`.id(selectedProfile)`) so a change tears down + rebuilds VMs/capability store cleanly (the iOS analogue of Mac's relaunch-to-flush-state).
3. Ensure capability store + per-tab context ids rebuild with the new context.

## Tests
- With a selection set, `context.paths.stateDB/memoriesDir/...` resolve under `profiles/<name>`.
- Changing selection changes the derived paths; default selection → base paths.

## Audit
- Fresh-eyes: no stale context captured by long-lived VMs; soft-disconnect/caches keyed by serverID not polluted across profiles; UserHomeCache (keyed by serverID) still correct (home is $HOME, not profile — unaffected).

## Commit
- `feat(ios,profiles): scope direct-file reads to selected profile via remoteHome (#120)`

## Artifacts



