---
title: Milestone 1 Implementation Spec — First-Class Project Object
type: note
permalink: scarf-design/projects-amazing/milestone-1-implementation-spec-first-class-project-object
tags:
- design
- projects
- phase-1
- milestone-1
- impl-spec
- ready-to-build
---

> **Status: READY TO BUILD.** File-anchored implementation spec for Milestone 1, synthesized from 3 scoping passes against `feat/projects` (post-v0.16 main). Implements [[First-Class Project Model (Phase 1)]]. Build this in a fresh session.

## Key reconciliations (do NOT reinvent)
- The design's "per-server fleet index `~/.hermes/scarf/projects.json`" **already exists** as Scarf's registry — `ProjectDashboardService` ↔ `ProjectRegistry`/`ProjectEntry` (`ScarfCore/Models/ProjectDashboard.swift`, `ScarfCore/Services/ProjectDashboardService.swift`). **EXTEND it** (add UUID + binding fields); don't create a parallel index.
- Per-project `<project>/.scarf/` already holds `dashboard.json`, `template.lock.json`, `manifest.json` (← `modelPresetID`, `kanbanTenant`, config schema), `config.json` (Keychain URIs), `slash-commands/`. The new canonical **`project.json` sits alongside** these (orthogonal to `template.lock.json`).
- `ProjectEntry.id` is currently the **display name** (no UUID). Minting a stable UUID is the one breaking-ish change — reconcile by adding `id: UUID` to `ProjectEntry`/registry + a one-time migration.
- Sessions-per-project = `SessionAttributionService.sessionIDs(forProject: path)` (`~/.hermes/scarf/session_project_map.json`).

## Build order

**1. `ScarfProject` model** — `ScarfCore/Sources/ScarfCore/Models/ScarfProject.swift` (NEW)
Codable per design lines 35–56: `id: UUID`, `name`, `rootPath`, `createdAt/updatedAt`, `modelPresetId`, `scopedToolsets/Skills` (DEFERRED — empty; see Decision #2 / upstream NousResearch/hermes-agent#45958), `board` (kanban slug), `cronJobIds`, `memoryNamespace`, `secretsScope` (names only), `templateLockRef`, `hostBindings: [{serverId, rootPath, materializedAt}]`.

**2. `ProjectStore` service** — `ScarfCore/Sources/ScarfCore/Services/ProjectStore.swift` (NEW). Mirror `ProjectDashboardService` (context-aware, transport-independent):
- `load(projectPath) -> ScarfProject?` ← `<project>/.scarf/project.json`
- `save(_:) throws` → write `.scarf/project.json` + upsert into the registry index
- `list() -> [ScarfProject]` ← the (extended) registry
- `derive()` migration: per `ProjectEntry`, build `ScarfProject` from `.scarf/manifest.json` (`modelPresetID`, `kanbanTenant`) + cron tags (`[tmpl:id]`/`[proj:id]` in `~/.hermes/cron/jobs.json`) + `config.json` secret keys + `template.lock.json` presence. **Additive, idempotent, non-destructive.**
- Reconcile: add `id: UUID` (+ binding fields) to `ProjectEntry`; migrate name-keyed → uuid-keyed (keep `name`).

**3. Invert the AGENTS.md renderer** — `Core/Services/ProjectAgentContextService.swift` (~`renderBlock` lines 128–207). Change `renderBlock(for: ProjectEntry)` → `renderBlock(for: ScarfProject)`; feed the managed block from `ScarfProject` fields instead of ad-hoc manifest/cron reads. **PRESERVE the invariants**: SECRET-SAFE (field names + `" (secret — name only…)"`, never values, ~line 278), IDEMPOTENT (skip write when `outData == existingData`, ~94), BOUNDED (`ProjectContextBlock.applyBlock` marker splice), NON-FATAL (`try?` + log). Keep `ProjectAgentContextServiceTests` (idempotency + secret-safety) green; update to the new signature.

**4. `ProjectCockpitView`** — `Features/Projects/Views/ProjectCockpitView.swift` (NEW). Add as a `DashboardTab.cockpit` tab in `ProjectsView.swift` (enum ~line 90, switch ~line 454) — keeps it inside the Projects feature (recommended over a new sidebar section).
- **Header**: name · path · bound model (`modelPresetId` → `ModelPresetService`) · host badges (`hostBindings`).
- **Panels** (tab bar): REUSE `ProjectSessionsView` + `ProjectKanbanTab` (gate `hasKanban`); NEW lightweight panels — Context (read-only AGENTS.md block preview), Cron (`ProjectCronViewModel` filtering `[proj:]`/`[tmpl:]` by project), Memory (MEMORY.md marker), Secrets (names from `secretsScope`), Templates (`templateLockRef`). **Mini-apps panel → Milestone 2** (gate `hasDashboardCommand`).
- **DI**: `serverContext` + `hermesCapabilities` via environment; scoped panel VMs mirror `CronViewModel(context:)`; cache via `AppCoordinator.featureViewModel(for:make:)` if needed.

**5. Wire creation** — `Core/Services/ProjectScaffolder.swift` `scaffold(...)` currently writes dashboard + AGENTS.md + registers `ProjectEntry` with NO UUID. Add: mint UUID, write `.scarf/project.json` via `ProjectStore`, register with the UUID.

## Decisions baked in
Store = repo-resident `.scarf/project.json` + extend existing registry as index (#1). Tool/skill scoping DEFERRED — empty, unblocks on hermes-agent#45958 (#2). Kanban = board-per-project via v0.16 `--board`, reuse `KanbanTenantResolver`'s `scarf:<slug>` (#3). Mini-apps not in M1 (#4).

## Invariants to carry
SECRET-SAFE · IDEMPOTENT · BOUNDED · NON-FATAL · PORTABLE (`.scarf/project.json` travels with the repo) · REVERSIBLE.

## Open implementation question
Add `id: UUID` to `ProjectEntry` and migrate (recommended — single source of truth) vs. layer `ScarfProject` separately with a name↔uuid map. Recommend the former.

## Reuse vs new
REUSE: `ProjectSessionsView`/VM, `ProjectKanbanTab`, `ProjectDashboardService` (pattern), `SessionAttributionService`, `ProjectModelPresetReader`/`ModelPresetService`, `KanbanTenantResolver`, `ProjectConfigKeychain`.
NEW: `ScarfProject`, `ProjectStore`, `ProjectCockpitView` + 5 lightweight panels (+ scoped VMs), the `renderBlock` refactor, scaffolder UUID minting.

## Relations
- implements [[First-Class Project Model (Phase 1)]]
- relates_to [[Mini-App Bridge Contract (Phase 1)]]
