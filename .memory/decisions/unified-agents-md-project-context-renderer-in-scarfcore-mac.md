---
title: Unified AGENTS.md project-context renderer in ScarfCore (Mac + iOS byte-identical)
type: note
permalink: scarf/decisions/unified-agents-md-project-context-renderer-in-scarfcore-mac
created: 2026-06-28
updated: 2026-06-28
source_sha: f738298a03f75c6124b729b6cc6f79a29d15bf6e
source_paths: scarf/Packages/ScarfCore/Sources/ScarfCore/Services/ProjectContextBlock.swift
---

## Decision (2026-06-28, chosen by Alan)

There is now ONE renderer for the Scarf-managed `<project>/AGENTS.md` block: `ProjectContextBlock.renderManagedBlock(ManagedBlockInput)` in ScarfCore, fed by `ProjectStore.renderAgentContextBlock(for: ScarfProject)`. Both the Mac app and ScarfGo (iOS) call it, so they emit BYTE-IDENTICAL blocks for identical on-disk state.

## Why

Before: the Mac had a rich renderer (`ProjectAgentContextService.renderBlock`) with cron jobs, config fields, template, Kanban tenant, lock, and the static "Scarf platform reference" section; iOS had a separate `ProjectContextBlock.renderMinimalBlock` that emitted ONLY name/dir/dashboard/slash. Because `applyBlock` replaces the marker region, an iOS project-chat start OVERWROTE a richer Mac-written block → cron/config vanished from the agent's context; the block flip-flopped by last-writer. This violated the cross-platform byte-identical invariant stated in `ProjectContextBlock.swift`. Impact: for projects whose work is scheduled jobs (self-learning agents + cron), the iOS agent was blind to them. (Alan corrected an initial "low priority / resume-staleness" mis-scoping — cron is often the bulk of a project's work.)

## Shape

- `ProjectContextBlock` (ScarfCore): pure `renderManagedBlock` + shared formatters `configFieldsLine(fields:)` and `cronLines(from:projectId:templateId:)`. `renderMinimalBlock` DELETED.
- `ProjectStore` (ScarfCore): `agentContextBlockInput(for:)` / `renderAgentContextBlock(for:)` gather inputs cross-platform via existing readers (`templateInfo`, `loadCronJobs`, `KanbanTenantReader`, `ProjectSlashCommandService`) + a new secret-safe `config.schema` projection. Works on Mac and over iOS SFTP.
- Mac `ProjectAgentContextService.renderBlock` is now a thin delegate to `ProjectStore.renderAgentContextBlock`; its inline renderer + private helpers were removed. Rendered output is byte-identical to before (verified by diffing string literals — only variable spellings changed).
- iOS `ChatController.writeProjectContextBlock(projectPath:projectName:)` shared helper, wired into BOTH the new-project-chat AND resume paths. Resume previously wrote NO block, so cron/config changes are now refreshed on every project-scoped start (matching the Mac's "rewrite on every project-scoped chat start").

## Invariant going forward

Do NOT add a second/divergent block renderer. Any change to block content goes in `renderManagedBlock` (+ formatters) so Mac and iOS stay byte-identical. The cron/config/template/kanban field SOURCES are the lightweight transport-based readers in `ProjectStore` — keep them the single gather path.

## Verification

ScarfCore 775/775; new `ProjectContextBlockManagedTests` (cron filter/format, config fields secret-safe, full block, idempotency); `M9SlashCommandTests` migrated to the unified renderer; Mac `ProjectAgentContextServiceTests` 13/13 (byte parity + secret-safety + idempotency); iOS app `scarf mobile` builds. Commit f738298 (after the process-cwd fix a58a1cf).

## Relations
- relates_to [[scarf/architecture/scarfgo-ios-does-not-load-project-context-process-cwd-gap]]
- relates_to [[scarf/features/project-scoped-chat-and-agents.md-context]]
