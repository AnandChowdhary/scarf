---
title: Task.detached capture lists must be explicit
type: note
permalink: scarf/conventions/task-detached-capture-lists-must-be-explicit
tags:
- concurrency
- swift6
- conventions
- rule
- audit-2026-06-13
created: 2026-06-13
updated: 2026-06-13
source_sha: 6a12139b218190d8a99ba679bd1a191c0bc13396
source_paths: scarf/scarf/Features/MCPServers/ViewModels/MCPServersViewModel.swift, scarf/scarf/Features/Plugins/ViewModels/PluginsViewModel.swift, scarf/scarf/Features/Chat/Views/RichChatInputBar.swift
source_paths_inferred: true
---

## Observations
- [rule] 🚨 Every `Task.detached` must carry an explicit capture list — `[weak self]` by default (use optional chaining), or `[self]` only when the task is short-lived and the owner is guaranteed to outlive it. Referencing `self` solely inside a nested `await MainActor.run { }` STILL counts as a capture and must be explicit. #rule
- [pattern] Under Swift 6 strict concurrency the implicit form is a compile error (a warning under the project's current `SWIFT_APPROACHABLE_CONCURRENCY`). When fixing one site in a file, audit the whole file — these violations cluster.
- [check] Quick audit: `grep -rn 'Task.detached {' --include="*.swift" scarf` then check each for a `[ … ]` capture list.
- [history] 2026-06-13 Cycle 1: `MCPServersViewModel.swift` 9 sites (96/118/136/148/165/207/240/265/279; correct pattern at L63), `PluginsViewModel.swift:110,140` (correct at L46), `RichChatInputBar.swift:535,574`. #history

## Relations
- relates_to [[Scarf Architecture Rules]]
- relates_to [[Store cancellable handles for off-main remote work]]
