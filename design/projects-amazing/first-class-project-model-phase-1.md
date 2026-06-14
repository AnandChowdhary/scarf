---
title: First-Class Project Model (Phase 1)
type: note
permalink: scarf-design/projects-amazing/first-class-project-model-phase-1
tags:
- design
- projects
- phase-1
- proposal
- fleet
---

> **Status: PROPOSAL (draft for review).** Phase-1 design for "make projects amazing." Not yet built. Pairs with [[Mini-App Bridge Contract (Phase 1)]]. Authored 2026-06-13 alongside the Hermes v0.16 parity pass.

## Why

Today a "project" in Scarf is **implicit** — its identity is smeared across half a dozen places, each owned by a different service:

| Facet | Where it lives today | Owner |
|---|---|---|
| Session attribution | `~/.hermes/scarf/session_project_map.json` (sidecar; ACP has no project hook, state.db has no cwd) | `SessionAttributionService` |
| Agent context | managed block in `<project>/AGENTS.md` between `<!-- scarf-project:begin/end -->` | `ProjectAgentContextService` |
| Template install | `<project>/.scarf/template.lock.json` | `ProjectTemplateInstaller/Uninstaller` |
| Tasks | a Kanban tenant / board (one global `~/.hermes/kanban.db`) | Kanban services |
| Cron | `hermes cron` jobs (no project tag today; templates use `[tmpl:<id>]`) | cron views |
| Model | a bound Model Preset, applied via ACP `session/set_model` | Model Presets |
| Memory | a `MEMORY.md` block between markers | template installer |
| Secrets | Keychain refs (names only ever surfaced) | Keychain layer |

There is **no single object or view that owns a project across these facets**, and nothing that answers *"what is this project, across the hosts it lives on?"* That gap is the wedge: Hermes v0.16 ships *profiles*, not *projects-as-portfolios*. This doc promotes Project to a first-class, fleet-aware entity and the cockpit that renders it.

## The entity — `ScarfProject`

A Scarf-owned manifest. **Canonical record is repo-resident** at `<project.path>/.scarf/project.json` (travels with the repo, versionable, mirrors the existing `template.lock.json` placement), with a per-server **fleet index** at `~/.hermes/scarf/projects.json` for fast listing without walking the filesystem.

```
ScarfProject {
  schemaVersion: Int
  id: UUID                 // stable; reuse template.lock id when present
  name: String
  rootPath: String         // absolute on this host
  createdAt, updatedAt: ISO8601

  // bindings (references, not copies)
  modelPresetId: String?
  scopedToolsets: [String]    // hermes toolset names (web, browser, …)
  scopedSkills:   [String]    // skill / bundle names
  board:          String?     // kanban board slug (v0.16 multi-board) or tenant filter
  cronJobIds:     [String]    // jobs tagged [proj:<id>] (mirror the [tmpl:<id>] convention)
  memoryNamespace: String?    // MEMORY.md marker id
  secretsScope:   [String]    // Keychain ref NAMES only — never values
  templateLockRef: String?    // path to template.lock.json if template-installed

  // fleet
  hostBindings: [{ serverId, rootPath, materializedAt }]   // where this id is live
}
```

**Invert the AGENTS.md block:** today `ProjectAgentContextService` assembles the managed block ad hoc. Refactor so the block is *rendered from `ScarfProject`* — the object becomes the structured source of truth; the block becomes a projection. This removes the duplicated assembly logic and keeps block ⇄ object in sync by construction.

## Facet aggregation (reuse, don't reinvent)

The Project object **references** existing stores; it does not duplicate them. Per facet:

- **Sessions** → filter `session_project_map.json` by `projectId` (already how `ProjectSessionsView` works).
- **Context** → render the AGENTS.md managed block from the object (see above).
- **Tasks** → own a Kanban board slug (v0.16 `--board`) or tenant filter against the one global `kanban.db`. Surface v0.16 `goal_mode`/`goal_max_turns` per card here.
- **Cron** → tag project jobs `[proj:<id>]` (mirror `[tmpl:<id>]`); `cronJobIds` is the index. Uninstall removes via `hermes cron remove`.
- **Model** → `modelPresetId`; applied at session boot via the existing `session/set_model` path.
- **Skills/Tools scope** → `scopedToolsets`/`scopedSkills`; *new* enforcement Scarf manages (see open questions for the enforcement seam).
- **Memory** → `memoryNamespace` → the `MEMORY.md` marker block (+ Hermes supermemory namespace if present).
- **Secrets** → `secretsScope` (names only; values stay in Keychain — SECRET-SAFE invariant).
- **Templates** → `templateLockRef`.

## The Project cockpit (UI)

One destination per project that aggregates every facet as panels — a "project lead" mission control:

- **Header**: name · root path · bound model · host badges (which servers it's live on).
- **Panels** (reuse existing views, scoped to the project): Sessions (`ProjectSessionsView`), Board (Kanban scoped), Context (AGENTS.md preview, read-only), Cron (filtered to `[proj:<id>]`), Skills/Tools scope, Memory (block preview), Secrets (names only), Templates, and **Mini-apps** (see [[Mini-App Bridge Contract (Phase 1)]]).

## Fleet dimension

Project is **per-server materialized but stable-id identified**. A **portfolio view** groups same-`id` projects across servers via `hostBindings`. "Apply to fleet" = materialize a project's config (model/skills/tools/cron) onto selected hosts — the entry point for config-as-policy (Phase-1 item #4). This is the capability a per-gateway client structurally cannot offer.

## Invariants (carry over the AGENTS.md ones — they are load-bearing)

- **SECRET-SAFE** — surface field/ref NAMES, never values.
- **IDEMPOTENT** — re-rendering the AGENTS.md block / fleet index from an unchanged object is byte-identical (no file-watcher churn).
- **BOUNDED** — never clobber user content outside managed markers.
- **NON-FATAL** — project-awareness failures use `try?` + log; never block chat from starting (matches `ChatViewModel.startACPSession`).
- **PORTABLE** — `.scarf/project.json` travels with the repo.
- **REVERSIBLE** — teardown via a lock manifest, like template uninstall.

## Migration

On first launch, **derive** `ScarfProject` records from existing state (no data loss): id + name + root from `session_project_map.json` and `template.lock.json`; `modelPresetId` from the bound preset; `templateLockRef` if present. The AGENTS.md block becomes a render of the derived object. Nothing is destroyed; the object is additive.

## Build seams (for the session that implements this)

- `ScarfProject` (Codable model, ScarfCore).
- `ProjectStore` (service: load/save canonical `.scarf/project.json` + fleet index; per `ServerContext`).
- `ProjectCockpitView` (the aggregate destination).
- Refactor `ProjectAgentContextService` to render its managed block **from** `ScarfProject`.
- Capability-gate fleet/board features via the existing [[Hermes Capability Gating Pattern]] (e.g. v0.16 `hasKanbanGoalMode`, multi-board).

## Open questions (need a decision before build)

1. **Canonical store** — repo-resident `.scarf/project.json` + `~/.hermes/scarf/projects.json` index (recommended) vs index-only. Recommend repo-resident for portability.
2. **Scoped tools/skills enforcement** — how is `scopedToolsets` applied at ACP session start? Options: per-session `-t <toolsets>` flag on `hermes acp`, vs writing project scope into config. Needs a verified Hermes seam (the `-t` flag exists on the CLI; confirm it threads to ACP).
3. **Board-per-project vs tenant filter** — given one global `kanban.db`, prefer a dedicated board slug per project (v0.16 multi-board) over the old tenant+time-window heuristic.

## Decisions (locked 2026-06-14) — supersede the Open questions above

1. **Canonical store → repo-resident + fleet index.** `.scarf/project.json` is canonical (portable, versionable); `~/.hermes/scarf/projects.json` is the per-server fast-list index.
2. **Scoped tools/skills → DEFERRED (not buildable on Hermes v0.16; verified).** `acp_adapter/session.py:_make_agent` HARDCODES `enabled_toolsets=["hermes-acp"]` (+ configured MCP servers) and ignores the `hermes acp -t/--toolsets` flag — a silent no-op for ACP, the trap [[Hermes Version Targeting Strategy]] warns about. There is NO per-session or per-process toolset seam in the ACP adapter today, and config-write can't override the hardcode either. Ship the Project object WITHOUT tool/skill scoping; revisit only after an upstream Hermes change (thread `-t` / a per-session `toolsets` param into `_make_agent` / `new_session`). Upstream ask FILED 2026-06-14: NousResearch/hermes-agent#45955 (issue) + #45958 (PR adding `SessionManager(default_toolsets)` + per-session `toolsets` on `session/new`). Scoping becomes buildable once that merges.
3. **Kanban → board-per-project.** Each project owns a dedicated board slug via Hermes v0.16 multi-board (`--board`).



## Relations
- builds_on [[Project-Scoped Chat and AGENTS.md Context]]
- builds_on [[Project Templates (.scarftemplate)]]
- relates_to [[Kanban Board Architecture (v2.7.5)]]
- relates_to [[Model Presets Feature]]
- relates_to [[Multi-Server Architecture (Scarf 2.0+)]]
- pairs_with [[Mini-App Bridge Contract (Phase 1)]]
- gated_by [[Hermes Capability Gating Pattern]]
