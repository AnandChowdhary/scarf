---
title: Fast test-iteration commands (swift test vs xcodebuild)
type: note
permalink: scarf/conventions/fast-test-iteration-commands-swift-test-vs-xcodebuild
tags:
- testing
- workflow
- swift-test
- xcodebuild
- iteration
- performance
created: 2026-06-15
updated: 2026-06-15
---

Fast feedback loop for running Scarf tests while iterating. The slow part is almost always the build (and accidentally pulling in UI tests), NOT the tests themselves.

## Observations
- [fast-path] ScarfCore logic (models/services/viewmodels under `scarf/Packages/ScarfCore`) → run via SwiftPM, NOT Xcode: `swift test --package-path scarf/Packages/ScarfCore --filter <SuiteName>`. Seconds to build, no app build, no simulator. This is the default loop while iterating on ScarfCore. #testing
- [app-target] App-target tests (`scarfTests` — e.g. ProjectAgentContextServiceTests, ProjectScaffolderTests, cockpit/scaffolder/renderer logic) → run ONE suite and skip UI: `xcodebuild test -project scarf/scarf.xcodeproj -scheme scarf -destination 'platform=macOS' -only-testing:scarfTests/<SuiteName>`. Drop the `/<SuiteName>` to run the whole `scarfTests` unit bundle without UI. #testing
- [avoid] NEVER run bare `xcodebuild test` while iterating — the `scarf` scheme's TestAction bundles BOTH `scarfTests` AND `scarfUITests` (app-launch UI tests, slow). Reserve the full sweep for a final pre-commit gate; use `-only-testing:scarfTests` for the fast unit pass. #gotcha
- [cost-model] Dominant cost is the app-target Swift COMPILE, not test execution (e.g. ProjectStoreTests = 8 tests in ~13ms; ProjectScaffolderTests = 3 in ~9ms). Prefer ScarfCore `swift test` while tweaking — it recompiles a fraction of the code. Only reach for xcodebuild once you've touched app-target files. #performance
- [streaming] Pipe live runs through `grep --line-buffered`, never `| tail` — tail buffers the whole stream and shows nothing until xcodebuild fully exits (incl. the slow result-bundle/coverage finalization after the last test). #gotcha
- [isolation-keep] Disk-integration tests deliberately use a fresh per-test temp Hermes home — do NOT consolidate into one shared fixture to "save setup". Registry-writing tests (save/derive/scaffold) assert on exact registry counts and would contaminate each other, forcing `.serialized` and losing parallelism. Per-test temp dirs are microseconds; isolation is the point. See [[ScarfCore tests inject a temp Hermes home via ServerContext.local(home:)]]. #testing

## Relations
- relates_to [[ScarfCore tests inject a temp Hermes home via ServerContext.local(home:)]]
- relates_to [[Build and Release Workflow]]
