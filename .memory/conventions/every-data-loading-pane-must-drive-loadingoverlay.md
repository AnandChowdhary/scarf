---
title: Every data-loading pane must drive .loadingOverlay()
type: note
permalink: scarf/conventions/every-data-loading-pane-must-drive-loadingoverlay
tags:
- hig
- swiftui
- ux
- conventions
- audit-2026-06-13
reviewed: 2026-06-15
created: 2026-06-13
updated: 2026-06-15
reviewed_by: human
---

## Observations
- [rule] 🚨 When a view loads data asynchronously (any `.task`/`.onChange` calling a ViewModel `load()`), the ViewModel must expose `isLoading: Bool` and the view must apply `.loadingOverlay(viewModel.isLoading, label: "Loading …", isEmpty: viewModel.<collection>.isEmpty)`. Treat the overlay as a required part of a data pane, not optional polish. #rule
- [pattern] `.loadingOverlay()` lives in `LoadingOverlay.swift` and is used correctly across Dashboard, Activity, Settings, Memory, Plugins, Health, CredentialPools, Cron, MCPServers, Insights, Sessions, Logs. Skipping it leaves users on blank/stale content during SSH fetches. For tail-poll loops (e.g. Logs's 2s tail), do NOT toggle `isLoading` — only set it on initial load / explicit switch — so the overlay doesn't flash on every poll.
- [check] For each `Features/*/Views/*View.swift` with `.task { await viewModel.load() }`, confirm a matching `.loadingOverlay(` and an `isLoading` on the VM.
- [history] 2026-06-13 Cycle 3: originally `InsightsView.swift:21-47` (stale on period change), `SessionsView.swift:43-77` (VM lacked isLoading), `LogsView.swift:17-28` (VM lacked isLoading). Fixed via t-aud07 — `SessionsViewModel`/`LogsViewModel` now expose `isLoading` and Insights/Sessions/Logs all apply the overlay. #history

## Relations
- relates_to [[Scarf Design System (ScarfDesign)]]
