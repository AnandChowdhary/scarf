---
id: t-dfc8c0e0
title: B4: docs/wiki/memory sync + fresh-eyes integration audit for #120
status: todo
added: 2026-06-25
---

## Description

Parent: t-873f7df9 (#120 Design B). Final integration audit across the whole feature + bring knowledge base and user docs up to date once behavior changes.

## Plan

## Plan
1. Update memory: ScarfGo iOS Companion App note (profiles no longer read-only on iOS; describe per-connection scoping); ensure the verified Hermes HERMES_HOME/-p facts + Design-B decision notes are present and linked.
2. Update wiki (ScarfGo / Profiles page) + README "What's New" entry (release-time) describing phone profile scoping.
3. Full fresh-eyes integration audit (ideally a fresh subagent): end-to-end switch flow, all surfaces consistent (dashboard/memory/cron/sessions/gateway/chat), no host active_profile mutation, no stale state across switches, tests are real (not checkbox).
4. Address audit findings; final verification build.

## Commit
- `docs(ios,profiles): document per-connection profile scoping; memory/wiki sync (#120)`

## Artifacts



