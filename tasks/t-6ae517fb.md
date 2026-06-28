---
id: t-6ae517fb
title: Spike: gateway-WS real-time cross-surface push
status: ideas
added: 2026-06-21
priority: low
---

## Description

**RECOMMENDATION (assessed 2026-06-28): SKIP / leave in ideas — lowest ROI of the follow-ups.** Grounded against installed + latest Hermes v0.17: there is NO client-subscribable gateway WebSocket / event-bus surface to build on (the `websockets` dep is transitive; "Tool Gateway" = tool routing; the messaging "gateway" is the platform bridge, not a Scarf-subscribable agent-output stream). The per-session ACP stream (`scarf.onEvent` → `MiniAppAgentSession`) already delivers live output and covers the real use cases. A spike now would be open-ended research with no seam. Revisit ONLY if (a) Hermes ships a subscribable multi-consumer event bus AND (b) a concrete multi-window/background-push need appears.

---

Optional exploratory spike from the projects-amazing build order (the "+ gateway-WS spike" attached to the orchestration cockpit). Today mini-apps + the cockpit get live agent output via the per-session ACP stream (`scarf.onEvent` → the per-mini-app `MiniAppAgentSession`). A Hermes gateway WebSocket subscription would enable live CROSS-surface push — one agent's output streamed to multiple open surfaces/windows at once, and push without a bound ACP session. Not required (everything works on the per-session stream today); "pays off later" per the Mini-App Bridge Contract. Scope: prototype subscribing to the gateway WS and fanning events to all open surfaces. The one optional/exploratory item left from the Phase-1 plan.

## Plan

ASSESSED 2026-06-28 — recommend DEFER (keep in ideas). Grounded against installed Hermes v0.17.0: no client-subscribable gateway WebSocket / event-bus surface found for cross-surface push. The `websockets` dep in uv.lock is transitive; "Tool Gateway" (README) is tool-routing (web search / image gen / TTS), and the messaging "gateway" is the platform-bridge, not a Scarf-subscribable agent-output stream. The per-session ACP stream (scarf.onEvent → MiniAppAgentSession) already delivers live output and works today. A spike would be open-ended research with no obvious Hermes seam to build on → low ROI now. Revisit IF Hermes ships a subscribable event bus / multi-consumer session stream. Not forced.

## Artifacts



