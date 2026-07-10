---
title: Store cancellable handles for off-main remote work
type: note
permalink: scarf/conventions/store-cancellable-handles-for-off-main-remote-work
tags:
- concurrency
- performance
- ssh
- conventions
- audit-2026-06-13
reviewed: 2026-06-15
created: 2026-06-13
updated: 2026-06-15
reviewed_by: human
---

## Observations
- [rule] 🚨 When a ViewModel launches off-main remote work (SSH round-trips, backups, multi-call loads), STORE the `Task` handle and cancel it on view disappear so navigating away stops in-flight network/subprocess work. #rule
- [pattern] References: `DashboardViewModel.inFlightLoad` (guards overlapping loads + cancellable) and `HealthViewModel.loadTask` + `cancelLoad()` (assigned + cancelled in `.onDisappear`, with `Task.isCancelled` checked between the 5 SSH round-trips). `BackupServerSheet` calls `viewModel.cancel()` in `.onDisappear` so dismissing mid-backup cancels the remote `tar`/SSH work. `.task` self-cancels and is preferred where the work belongs to a single view's lifetime. `RemoteBackupService` already threads `Task.checkCancellation()` through its stages — but only fires if the Task is actually cancelled.
- [check] Look for `Task.detached`/`Task {` launched from a VM method whose handle isn't assigned to a stored property and has no `.onDisappear` cancel.
- [history] 2026-06-13 Cycle 2: originally `HealthViewModel.swift:144-176` (6+ SSH round-trips keep running after tab-away) and `BackupServerSheet.swift:31-34` (no cancel-on-dismiss). Fixed via t-aud11 (Health) and t-aud17 (BackupServerSheet). #history

## Relations
- relates_to [[Task.detached capture lists must be explicit]]
- relates_to [[Prefer .task over .onAppear for view-load fetches behind switch-based navigation]]
