---
id: t-1fef0a83
title: iOS: pool CitadelServerTransport per server (fix gh#112 chat-init churn)
status: doing
added: 2026-06-25
priority: high
---

## Description

gh#112 / [[t-2c5982]] root cause. ScarfGo chat-init fails with "Couldn't save model.provider … Transport refused the command" AND Settings shows model/source empty while Platforms populate, on hosts where the same `hermes config set` works by hand and reproduces across two unrelated hosts.

PROVEN from code:
- "Transport refused the command" (ChatView.swift:1445) only fires when `runProcess` THROWS, which on iOS happens ONLY at `connectionHolder.ssh()` → `SSHClient.connect()` (CitadelServerTransport.swift:457). Every post-connect failure returns a ProcessResult (exit code), never throws. So the symptom = the SSH handshake itself failed, NOT a command rejection.
- `ServerContext.makeTransport()` returns a FRESH `CitadelServerTransport` per call (ServerContext.swift:163); the iOS factory (ScarfIOSApp.swift:35) news one up each time with its own `ConnectionHolder` (sshClient=nil). So every file read / exec opens a brand-new SSH handshake; close-on-dealloc is fire-and-forget. Settings-load + chat-init churn many short-lived handshakes → connect() starts failing.
- Reads swallow transport failure to "empty": `fileExists` try?→false (CitadelServerTransport.swift:118) → `readTextThrowing` returns nil = "file absent" (ServerContext.swift:330). Why "Pick a model"/"View source" read empty while Platforms (cached after one good read) populate.
- The factory comment (ScarfIOSApp.swift:31-34) FALSELY claims "not a new SSH handshake".

## Plan

Design B-compatible: profile scoping is per-OP (HERMES_HOME from config.remoteHome at asyncRunProcess:476 + SFTP remoteHome paths), so pool key = ServerID with stored SSHConfig (Hashable) as staleness check. Profile switch → remoteHome changes → config differs → pool replaces (close old conn, open new). Bounded per server/profile, not per op.

Steps:
1. New `CitadelTransportPool.shared` (ScarfIOS) — NSLock-guarded [ServerID: Entry(config, transport)]; `transport(for:config:make:)` get-or-create + replace-on-config-change (close superseded off-thread); `evict(id)` + `evictAll()` async close. Mirrors UserHomeCache.shared / ResultBox NSLock pattern.
2. Wire iOS `sshTransportFactory` through the pool; fix the false "not a new SSH handshake" comment.
3. Eviction: RootModel.softDisconnect (evict id), forget(id) (evict id), disconnect (evictAll); ScarfGoCoordinator.setScenePhase(.background) → evictAll (ACP chat channel handles its own scene phase separately, so safe).
4. Diagnostic: chat preflight catches the thrown connect error and passes it into preflightFailureMessage so the else-branch shows the real reason instead of a generic line.

Test (real, not checkbox): pool reuse (same instance for same id+config), replace-on-config-change (new instance + old closed), evict closes, concurrency (N parallel transport(for:) calls → one instance, no race) — via injected counting make-closure, no live SSH. 
Audit: fresh-eyes adversarial pass incl. profile-switch transition races + SFTP-sharing concurrency.

Out of scope (separate): F2/[[t-ios-cfg-get]] Docker read-path via `hermes config get`. Pooling fixes host-1 fully + host-2 write churn.

## Artifacts

Implemented + tested + audited (not pushed).

Code:
- NEW scarf/Packages/ScarfIOS/Sources/ScarfIOS/CitadelTransportPool.swift — shared pool, NSLock-guarded [ServerID: (SSHConfig, CitadelServerTransport)], transport(for:config:make:)/evict/evictAll.
- ScarfIOSApp.swift — factory routes through pool (false "not a new SSH handshake" comment corrected); evict on softDisconnect/forget, evictAll on disconnect.
- ScarfGoCoordinator.swift — evict own server on scene-phase .background.
- ChatView.swift — runConfigSet captures the THROWN connect error; preflightFailureMessage shows it ("Couldn't open an SSH session…") instead of the generic "Transport refused" line.

Test-enablement (separate commit): CitadelServerTransport #if !os(iOS) makeProcess stub + Package.swift .macOS v14→v15 so `swift test` runs on macOS.

Tests: scarf/Packages/ScarfIOS/Tests/ScarfIOSTests/CitadelTransportPoolTests.swift — 6 tests (reuse, profile-switch replace, coexistence, evict, evictAll, 64-way concurrency→1 instance). Full ScarfIOS suite green (15/15). iOS app ("scarf mobile") BUILD SUCCEEDED.

Audit: Mac app does NOT link ScarfIOS (only "scarf mobile" does) → macOS changes have zero shipping impact. Residuals: shared SFTPClient wider concurrency (pre-existing pattern, verify on-device); bounded self-healing orphan-reconnect on profile switch (not per-op churn). See [[iOS transport must be pooled per (ServerID, SSHConfig) — un-pooled makeTransport churns SSH connections]].

Fixes host-1 (native) fully + host-2 (Docker) write churn. Docker READ-path (config inside container) remains [[t-ios-cfg-get]].

