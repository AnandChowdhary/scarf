---
title: TestRegistryLock: acquire after fallible setup, and it deadlocks across parallel suites
type: note
permalink: scarf/conventions/testregistrylock-acquire-after-fallible-setup-and-it-deadlocks-across-parallel-suites
tags:
- testing
- gotcha
- deadlock
- testregistrylock
- concurrency
- swift-testing
- isolation
---

`TestRegistryLock` (scarfTests/ProjectTemplateTests.swift) is a global cross-suite `NSLock` that serializes app-target tests touching the real `~/.hermes/scarf/projects.json` + the global `SCARF_HERMES_HOME` env. It has bitten twice with the SAME symptom: a hung `scarf` test host (Debug build), reparented under `launchd`, 0% CPU, stuck for hours at `CatalogViewModelTests.makeTmpHome → TestRegistryLock.acquireAndSnapshot → _pthread_mutex_firstfit_lock_slow → __psynch_mutexwait`. There are TWO distinct failure modes — don't conflate them.

## Observations

- [leak-on-throw] **Failure mode 1 (fixed 2026-06-16).** A `makeTmpHome()`-style helper that acquires the lock at the TOP, then does fallible `try` filesystem work, and relies on the CALLER's `defer { teardown }` to release, **leaks the lock if the helper throws** — the caller never binds the fixture, so the `defer` never installs, and every later registry-touching test in the process deadlocks on `acquireAndSnapshot`. Fix: acquire the lock AFTER all fallible setup but BEFORE the `setenv(SCARF_HERMES_HOME, …)` redirect (so a throw can't leak it, and the snapshot still captures the REAL registry); ensure nothing between the acquire and the caller's defer can throw. Applied to the three helper-pattern suites: `CatalogViewModelTests`, `CatalogServiceTests`, `InstalledTemplatesIndexTests`. The direct-in-test shape `let s = acquireAndSnapshot(); defer { restore(s) }` (ProjectsViewModelTests, TemplateE2ETests) was already safe. #gotcha

- [concurrency-deadlock] **Failure mode 2 (FIXED 2026-06-16 — structural).** `TestRegistryLock` is a BLOCKING `NSLock` contended across PARALLEL suites — Swift Testing only serializes WITHIN a suite (`.serialized`), different suites still run concurrently. Some lock-using suites are `@MainActor` (e.g. `CatalogViewModelTests`), so they call `NSLock.lock()` **on the main thread**. If a main-actor suite blocks the main thread on the lock while another parallel suite (holding the lock) needs the main thread to reach its `restore`/release, they deadlock. It's timing-dependent/flaky: the full `-only-testing:scarfTests` bundle may pass, but **batching several lock-using suites together** (`-only-testing:scarfTests/CatalogViewModelTests -only-testing:.../CatalogServiceTests -only-testing:.../InstalledTemplatesIndexTests …`) reliably hangs. **Resolution (the preferred path):** `TestRegistryLock` is DELETED. Every registry/sidecar/catalog-cache-touching app-target suite — `CatalogViewModelTests`, `CatalogServiceTests`, `InstalledTemplatesIndexTests`, `ProjectsViewModelTests`, `SessionAttributionServiceTests`, and the three `ProjectTemplate{Installer,Uninstaller,ConfigInstall}Tests` — now isolates via a per-instance `ServerContext.local(home:)` obtained through the shared `scarfTests/TempHermesHome.swift` helper ([[ScarfCore tests inject a temp Hermes home via ServerContext.local(home:)]]). No global `SCARF_HERMES_HOME` env, no shared real registry, no cross-suite lock, no `.serialized` on those suites — so nothing blocks the main thread and the suites are genuinely parallel-safe. The ONLY remaining global-`SCARF_HERMES_HOME` mutator is `ScarfHermesHomeOverrideE2ETests` (whose entire purpose is proving the env steers `ServerContext.local.paths`); it keeps `.serialized` + env save/restore but no longer needs the lock, because every other suite now bypasses the env via `localHomeOverride`. Bonus: the config-install test previously wrote the developer's REAL `~/.hermes/.env` via `KeychainEnvMirror` (the old lock only snapshot/restored `projects.json`, never `.env`) — now sandboxed to the temp home. Verified: the batched 4-suite repro is `27 tests / 4 suites` passing in ~0.03s with no hang across repeated runs; full `-only-testing:scarfTests` is `216 tests / 36 suites`, 0 failures. #deadlock #resolved

- [ops-stop-runs] **Never `pkill` the `xcodebuild` PARENT to stop a test run.** App-hosted XCTest/Swift-Testing runs in a separate `scarf.app` test host launched via launchd; killing `xcodebuild` orphans that host (reparented to `launchd`), where it can wedge for hours holding nothing useful. Kill the test HOST directly: `pkill -9 -f "DerivedData/scarf-.*Debug/scarf.app/Contents/MacOS/scarf"` (plus the `xcodebuild` pid). Also: **macOS has no `timeout` command** (exit 127) — don't wrap test runs in `timeout`; run in the background (harness-tracked) and kill the host explicitly if it hangs. #ops

- [scope] Neither failure mode is in product code — both are app-target test-infra. The fleet/portfolio work (M3) and its tests don't use `TestRegistryLock` (they use isolated per-instance temp homes) and never hang. #context

## Relations
- relates_to [[ScarfCore tests inject a temp Hermes home via ServerContext.local(home:)]]
- relates_to [[Fast test-iteration commands (swift test vs xcodebuild)]]
