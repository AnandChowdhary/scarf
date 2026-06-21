---
id: t-6ae517fb
title: Spike: gateway-WS real-time cross-surface push
status: ideas
added: 2026-06-21
priority: low
---

## Description

Optional exploratory spike from the projects-amazing build order (the "+ gateway-WS spike" attached to the orchestration cockpit). Today mini-apps + the cockpit get live agent output via the per-session ACP stream (`scarf.onEvent` → the per-mini-app `MiniAppAgentSession`). A Hermes gateway WebSocket subscription would enable live CROSS-surface push — one agent's output streamed to multiple open surfaces/windows at once, and push without a bound ACP session. Not required (everything works on the per-session stream today); "pays off later" per the Mini-App Bridge Contract. Scope: prototype subscribing to the gateway WS and fanning events to all open surfaces. The one optional/exploratory item left from the Phase-1 plan.

## Plan



## Artifacts



