---
title: Mini-App Bridge Contract (Phase 1)
type: note
permalink: scarf-design/projects-amazing/mini-app-bridge-contract-phase-1
tags:
- design
- mini-apps
- phase-1
- proposal
- webview
- bridge
- security
---

> **Status: PROPOSAL (draft for review).** Phase-1 design for Cowork-style mini-apps. Not yet built. Pairs with [[First-Class Project Model (Phase 1)]]. Webview-first path chosen for speed, free iOS parity, and agent-generability. Authored 2026-06-13.

## Concept

A **mini-app** is a small web surface (HTML/CSS/JS) that renders *inside* Scarf and talks to a bound Hermes session + the Scarf host through a narrow, versioned JS bridge. It is a **project facet** — shipped via `.scarftemplate`, dropped into a project, or **generated on the fly by the agent**. Because the surface is plain web + a tiny API, cheaper models can author mini-apps reliably. This is Scarf's leapfrog over a generic gateway GUI: a native, fleet-aware, project-scoped app platform on top of Hermes.

**Webview-first**, deliberately: fastest path, cross-platform (macOS + iOS ScarfGo for free), agent-can-generate, matches the Cowork canvas paradigm. A native SwiftUI panel-kit is a *later* parallel track, not v1. Prior art in-repo: the existing visualize/widget `sendPrompt(text)` global — the prompt bridge generalizes that pattern.

## Packaging

A mini-app is a directory:

```
miniapp.json        // manifest
index.html          // entry
*.js / *.css / …    // static assets, no build step required
```

`miniapp.json`:
```
{ "id": "kanban-burndown", "name": "Burndown", "version": "1.0.0",
  "entry": "index.html", "minBridgeVersion": "1.0",
  "permissions": ["query:kanban", "prompt", "events", "store"],
  "panelHint": { "preferredWidth": 420, "placement": "panel" },
  "generated": false }
```

**Locations** (registered in `ScarfProject.miniApps`):
- inside a `.scarftemplate` under `miniapps/<id>/` (extends the template format), or
- `<project>/.scarf/miniapps/<id>/` (project-local), or
- an agent-generated scratch dir (ephemeral, stricter defaults — see below).

## Rendering host

`MiniAppHostView` — a SwiftUI wrapper over `WKWebView`. Assets are served through a custom **`scarf-miniapp://` scheme handler** scoped to the mini-app's directory (NOT raw `file://` — see Security). The host binds a `projectId` and, optionally, an active `sessionId`.

## The bridge contract — `window.scarf` (the core deliverable)

Injected at document start; **versioned** (`scarf.version`). Calls are async request/response via `WKScriptMessageHandlerWithReply`, each validated + permission-checked host-side.

**Context (readonly)**
- `scarf.context` → `{ projectId, projectName, projectRoot, sessionId?, serverId, capabilities, locale, theme }` (capabilities = a safe subset of `HermesCapabilities`).

**Agent channel** (the important part)
- `scarf.prompt(text, opts?) → Promise<{ ok }>` — send a prompt to the bound ACP session. Maps to `session/prompt`. **Rate-limited** host-side to prevent runaway loops.
- `scarf.onEvent(cb)` — subscribe to streamed ACP events for the bound session (message chunks, tool calls, completion) so a mini-app renders live agent output. Maps to the `ACPEvent` stream. *(v1 uses the existing per-session ACP stream; live cross-surface push is where the gateway-WS spike pays off later.)*
- **No raw tool execution from web in v1.** Mini-apps drive the agent via `prompt` and *read* results; they never call Hermes tools directly. Security boundary, stated explicitly.

**Data channel** (read, whitelisted — never arbitrary SQL)
- `scarf.query(kind, params) → Promise<rows>` — a closed set of `kind`s backed by `HermesDataService` / kanban DB: `sessions`, `messages` (active-only, honoring the v0.16 `messages.active` filter), `kanban.tasks`, `cron.jobs`, `insights.tokens`.
- `scarf.kanban.read()` and (permission `kanban:write`) `scarf.kanban.move/create(...)` via the existing kanban service.

**Host channel**
- `scarf.store.get/set(key, value)` — per-(project, mini-app) persisted KV, sandboxed to `<project>/.scarf/miniapps/<id>/state.json`.
- `scarf.file.read(relPath)` — scoped to project root, **read-only**, permission `file:read`.
- `scarf.ui.toast(msg)` · `scarf.ui.setTitle` · `scarf.ui.requestClose` · `scarf.ui.resize(hint)`.

## Permissions model (the trust boundary)

`miniapp.json.permissions` declares every bridge surface used: `prompt`, `events`, `query:<kind>`, `kanban:write`, `file:read`, `file:write`, `store`, `net`. **Default-deny.** Before first run Scarf shows a **permission preview sheet** — load-bearing, exactly like the template-install preview (the user's only trust boundary). Web content can **never** reach secrets, `config.yaml`, `auth.json`, arbitrary filesystem, or tools — regardless of declared permissions.

## Security model (web content is untrusted, *especially* agent-generated)

- Serve assets via the **`scarf-miniapp://` scheme handler** scoped to the mini-app dir; no `file://` directory escape.
- Strict **CSP**; block all external network unless `net` is granted *with an allowlist*.
- Bridge over `WKScriptMessageHandlerWithReply` with a **unique per-instance handler**, schema-validated messages, host-side permission checks on every call.
- **Rate-limit** `prompt()`; **never** inject secrets/tokens into the web context.
- Agent-generated mini-apps carry a `generated: true` flag and **stricter defaults** (no `net`, no `file:write`) until the user explicitly elevates.

## Lifecycle

install (template / drop / agent-write) → permission grant → mount (bind project + optional session) → runtime (bridge calls) → persist (`store`) → unmount → uninstall (remove dir + state; **reversible** like templates).

## Agent-generated mini-apps (the Cowork flow)

The agent writes a mini-app dir into `<project>/.scarf/miniapps/<id>/` using its file tools; Scarf detects and surfaces it (`generated: true`, locked-down perms). This is "the agent builds you a bespoke surface for this task" — a table, an approval queue, a dashboard — rendered natively and bound to the session that made it.

## Versioning

Bridge is semver'd; `miniapp.json.minBridgeVersion` is checked at mount. On mismatch Scarf loads degraded or refuses — the capability-gating analogue for web surfaces.

## Build seams (for the session that implements this)

- `MiniAppManifest` (Codable), `MiniAppPermission` (enum).
- `MiniAppHostView` (WKWebView wrapper) + the `scarf-miniapp://` `WKURLSchemeHandler`.
- `ScarfMiniAppBridge` (the `WKScriptMessageHandlerWithReply` — maps calls to ACP client / `HermesDataService` / kanban / Keychain-free host APIs).
- `MiniAppStore` (sandboxed KV).
- Generalize the existing visualize `sendPrompt` into `scarf.prompt`.
- Compose mini-apps into `ProjectCockpitView` as panels.

## Open questions (decide before build)

1. **Scheme handler vs local loopback server** — recommend the `scarf-miniapp://` scheme handler (no port, no network surface).
2. **`kanban:write` in v1?** — recommend read-only v1; writes (move/create) behind an explicit permission once the read path is proven.
3. **iOS bridge parity** — `WKScriptMessageHandlerWithReply` works on iOS; confirm the scheme handler path under ScarfGo.
4. **Native panel-kit** — deferred parallel track for the few high-frequency surfaces (board, approvals, review) where native polish beats webview.

## Decisions (locked 2026-06-14)

- **Kanban writes → read-only v1.** Mini-apps read kanban/data; `kanban:write` (move/create) is deferred behind an explicit permission until the read path is proven — smaller trust surface for untrusted/agent-generated web content. (Open questions 1/3/4 — scheme-handler vs loopback, iOS bridge parity, native panel-kit — remain as written.)



## Relations
- pairs_with [[First-Class Project Model (Phase 1)]]
- relates_to [[Project Templates (.scarftemplate)]]
- relates_to [[Hermes Integration]]
- gated_by [[Hermes Capability Gating Pattern]]
