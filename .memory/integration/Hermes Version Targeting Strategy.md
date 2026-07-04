---
title: Hermes Version Targeting Strategy
type: note
permalink: scarf/integration/hermes-version-targeting-strategy
tags:
- hermes
- versioning
- capability-gating
source_sha: 6a12139b218190d8a99ba679bd1a191c0bc13396
source_paths: scarf/Packages/ScarfCore/Sources/ScarfCore/Services/HermesCapabilities.swift, scarf/Packages/ScarfCore/Sources/ScarfCore/Services/ModelCatalogService.swift, scarf/Packages/ScarfCore/Sources/ScarfCore/Services/ModelPreflight.swift
reviewed: 2026-07-04
created: 2026-05-29
updated: 2026-07-04
reviewed_by: claude-fable-5
source_paths_inferred: false
---

## Observations
- [current-target] Scarf targets Hermes v0.16.0 (v2026.6.5) as of 2026-06-13 (see [[Hermes v0.16 Compatibility Decisions]]) — was v0.15.0 (v2026.5.28, 'The Velocity Release'). v0.14.0 keeps the full v2.9 surface; all versions v0.6.0 through v0.15.0 are verified. Older hosts degrade gracefully #target
- [philosophy] Every release-gated UI surface is capability-gated via HermesCapabilities flags. Pre-target hosts must render byte-identical to prior Scarf versions — never throw on unknown CLI subcommands #gating
- [flag-grouping] Group HermesCapabilities flags at the top of the file by introducing release: `MARK: v0.14 (v2026.5.16) flags`, `MARK: v0.15 (v2026.5.28) flags`, etc. #convention
- [verification] Verify exact flag/config/wire shapes against the tagged Hermes source (e.g. `v2026.5.28`) BEFORE implementation — flags like HERMES_INFERENCE_MODEL silently no-op for ACP because `_make_agent` doesn't consult them #pitfalls
- [keep-in-sync] On every Hermes bump, reconcile ModelCatalogService.{overlayOnlyProviders, modelAliases, demotedProviders, imageGenModels, providerDisplayNameOverrides} against hermes_cli/{providers.py, models.py, xai_retirement.py}; for the provider tables run `scripts/check-hermes-tables.py <hermes-checkout-at-target-tag>` — it mechanically gates ModelCatalogService.providerAliases ↔ ALIASES, ModelPreflight.aggregatorProviders ↔ is_aggregator overlays, and overlayOnlyProviders ↔ overlays absent from models.dev (see [[Aggregator providers must skip the model/provider mismatch preflight]]); reconcile platform roster against plugins/platforms/ + gateway/platforms/; reconcile search/TTS backend lists #maintenance
- [schema] state.db schema has been unchanged since v0.11 (added messages.reasoning_content + sessions.api_call_count). v0.12–v0.15 require no DB migration; v0.16 adds a `messages.active` soft-delete column (FIRST schema change since v0.11) — Scarf schema-detects it via `hasMessagesActiveColumn` and conditionally applies `AND active = 1`. Scarf reads state.db and parses CLI output from `hermes status`, `hermes doctor`, `hermes tools`, `hermes sessions`, `hermes gateway`, `hermes pairing` with automatic schema detection for backward compatibility #schema
- [automatic-gains] Most v0.15 work (run_agent.py refactor, cold-start perf, promptware defense, session_search rebuild, Ink TUI, web dashboard, Docker s6, API-server REST) is server-side and benefits Scarf transparently with no code change #server-side

## Relations
- extends [[Hermes Capability Gating Pattern]]
- relates_to [[Hermes v0.15 Capability Gating Decisions]]