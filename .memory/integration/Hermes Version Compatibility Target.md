---
title: Hermes Version Compatibility Target
type: note
permalink: scarf/integration/hermes-version-compatibility-target
tags:
- hermes
- compatibility
- versioning
source_sha: 64bb87b88f785636aea2386ba3837723f7b81eec
source_paths: README.md, CLAUDE.md, scarf/Packages/ScarfCore/Sources/ScarfCore/Services/HermesCapabilities.swift, scarf/Packages/ScarfCore/Sources/ScarfCore/Services/HermesLogService.swift
reviewed: 2026-06-28
created: 2026-05-29
updated: 2026-07-10
reviewed_by: audit:claude-code (audit)
---

## Observations
- [target] Latest shipped Scarf is **v2.15.1** (aggregator-mismatch patch); **v2.16.0 is prepped and awaiting the maintainer cut** (branch feat/hermes-v0182-parity → main). The Hermes catch-up trail: v2.11.0 → Hermes v0.16.0; v2.12.0 → v0.17.0; v2.13.0/v2.15.0 Scarf-internal; **v2.16.0 → the Hermes v0.18 line, audited at v0.18.0 (v2026.7.1) and re-audited at v0.18.2 (v2026.7.7.2)** — see [[Hermes v0.18.0 Audit Findings]] and [[Hermes v0.18.2 Audit Findings]]. **Scarf's current Hermes target is v0.18.2 (v2026.7.7.2)**; v0.15+ remain fully supported, minimum v0.6.0. #current
- [compatibility] Minimum supported Hermes: v0.6.0 (2026-03-30). All versions v0.6.0 through v0.17.0 are verified. Older Hermes versions degrade gracefully — new behavior is capability-gated. #minimum
- [v017-target] v0.17.0 (v2026.6.19) shipped upstream 2026-06-19 and is Scarf's current target — caught up in Scarf v2.12 (see [[Hermes v0.17 Compatibility Decisions]]). The upstream surfaces Scarf reads — state.db schema, ACP wire, CLI verbs, config keys, model catalog — were verified entirely stable for v0.17, so it required no forced compatibility changes; Scarf added the WhatsApp/SimpleX/Telegram surfaces, curator-consolidation toggle, and session-cap. Every v0.16/v0.17 surface is capability-gated or schema-detected so older hosts render byte-identical. #status
- [schema] Scarf reads Hermes's SQLite state.db and parses CLI output from `hermes status`, `hermes doctor`, `hermes tools`, `hermes sessions`, `hermes gateway`, `hermes pairing`. Automatic schema detection provides backward compatibility (v0.16 added the `messages.active` soft-delete column — first schema change since v0.11; detected via `hasMessagesActiveColumn`. v0.17 introduced no further schema change). #schema
- [parsing] Log lines may carry an optional `[session_id]` tag between level and logger name; `HermesLogService.parseLine` treats the session tag as an optional capture group so older untagged lines still parse. #logs
- [sync-checklist] On each Hermes bump, keep in sync: `overlayOnlyProviders` / `modelAliases` / `demotedProviders` / `imageGenModels` (vs hermes_cli/providers.py + models.py + xai_retirement.py), the platform roster (vs plugins/platforms/ + gateway/platforms/), and the search/TTS backend lists. #maintenance

## Relations
- implements [[Hermes Capability Gating Pattern]]
- supersedes [[Hermes v0.15 Capability Gating Decisions]]
- relates_to [[Hermes v0.17 Compatibility Decisions]]