---
title: ScarfGo (iOS) does NOT load project context — process-cwd gap (the Mac fix never reached iOS)
type: note
permalink: scarf/architecture/scarfgo-ios-does-not-load-project-context-process-cwd-gap
created: 2026-06-28
updated: 2026-06-28
source_sha: 64bb87b88f785636aea2386ba3837723f7b81eec
source_paths: AGENTS.md, CLAUDE.md, scarf/scarf/Core/Services/ACPClient+Mac.swift, scarf/Packages/ScarfCore/Sources/ScarfCore/Transport/SSHTransport.swift, scarf/Packages/ScarfIOS/Sources/ScarfIOS/ACPClient+iOS.swift
---

## Summary

The macOS "project chat loads project context" fix (commits `b421280` new-chat + `5538e30` resume/reconnect, tasks t-565f8d45 / t-24594c4a) is **NOT mirrored on iOS (ScarfGo)**. A project-scoped chat on iOS spawns `hermes acp` from the SSH user's HOME, so Hermes never loads the project's `AGENTS.md` / `CLAUDE.md` / `.cursorrules` into the system prompt. The agent gets no project instructions/context. Audited 2026-06-28 (fresh-eyes, source-verified).

## Root cause — context loads from PROCESS cwd, not ACP session cwd

Hermes auto-reads the first matching context file (.hermes.md → HERMES.md → AGENTS.md → CLAUDE.md → .cursorrules) from the **process cwd** of `hermes acp`, NOT from the ACP `session/new` cwd. This is stated in-code twice:
- `scarf/scarf/Core/Services/ACPClient+Mac.swift:16-18` — "projectCwd … becomes the spawned hermes acp process's working directory, so Hermes loads that project's AGENTS.md context files (it reads them from the process cwd, not the ACP session cwd)."
- `scarf/Packages/ScarfCore/Sources/ScarfCore/Transport/SSHTransport.swift:447-454` — prepends `cd <cwd>; ` to the remote command "so Hermes loads its AGENTS.md (Hermes reads project context files from the process cwd, not the ACP session cwd)."

## What macOS does (both halves)
- `ACPClient.forMacApp(context:projectCwd:)` → `transport.makeProcess(…, cwd: projectCwd)`. Local sets `Process.currentDirectoryURL`; **remote prepends `cd <cwd>;`** to `bash -lc` (SSHTransport.makeProcess, gated `#if !os(iOS)`).
- `ProjectAgentContextService.refresh(for:)` writes the managed `<!-- scarf-project -->` block into `<project>/AGENTS.md` BEFORE `client.start()` (ChatViewModel.swift ~1146).

## What iOS does (the gap)
- `ACPClient.forIOSApp(context:keyProvider:)` (`scarf/Packages/ScarfIOS/Sources/ScarfIOS/ACPClient+iOS.swift:34`) has **no projectCwd param**. Command built at :78 is `PATH="…" [HERMES_HOME=…] exec hermes acp` — **no `cd`**. `hermes acp` runs in the SSH login dir (home). `SSHTransport.makeProcess(cwd:)` is `#if !os(iOS)` so iOS can't reach it; iOS uses `SSHExecACPChannel` (Citadel) instead.
- iOS DOES write the block over SFTP via `ProjectContextBlock.writeBlock(…, forProjectAt: projectPath)` in `ChatController.resetAndStartInProject` (`scarf/Scarf iOS/Chat/ChatView.swift:2211`), and DOES set the ACP **session** cwd via `newSession(cwd: projectPath)` (:2286) — but neither triggers context loading. So the block lands on disk and is never read by the agent.
- Resume path (`ChatView.swift` ~:2419) is worse: `resumeSession/loadSession(cwd: home)` + `forIOSApp` → no project cwd at all.

## Severity
Silent correctness bug with **misleading UI**: iOS shows the project chip + git-branch + project slash-commands and even surfaces a yellow banner if the AGENTS.md WRITE fails — all implying the agent has project context, when it does not. This is the same *class* of "project session doesn't carry its instructions" bug, present only on iOS.

## Fix shape (small, localized)
Thread `projectCwd` into `forIOSApp` → `makeSSHExecChannel`, and prepend `cd <quoted projectCwd>; ` before `PATH=… exec hermes acp`. `SSHExecACPChannel`'s own doc (line 57-58) anticipates a leading `cd …;`. Mirror SSHTransport's choices: `;` not `&&` (stale/missing dir degrades to home instead of failing the session) and `remotePathArg`-style quoting (`~/`→`$HOME/`, double-quote spaces/metachars). Apply to BOTH the new-chat (`startInternal`, projectPath branch) and resume paths. Caveat: keep working over the profile `HERMES_HOME=` prefix — `cd X; PATH=… HERMES_HOME=… exec hermes acp` is valid.

## Relations
- relates_to [[scarf/features/project-scoped-chat-and-agents.md-context]]
- relates_to [[scarf/decisions/project-context-file-injection-release-note-awareness-not-a]]
- relates_to [[scarf/architecture/scarf-go-i-os-companion-app]]
