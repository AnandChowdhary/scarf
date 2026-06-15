---
title: Hermes Version Compatibility Target
type: note
permalink: scarf/integration/hermes-version-compatibility-target
tags:
- hermes
- compatibility
- versioning
source_sha: f770fe49412e097d9b082179e1f96a83d3ebbc21
source_paths: README.md, CLAUDE.md, scarf/Packages/ScarfCore/Sources/ScarfCore/Services/HermesCapabilities.swift, scarf/scarf/Core/Services/HermesLogService.swift
reviewed: 2026-06-15
---

## Observations
- [target] Latest shipped Scarf is **v2.10.3** (tagged 2026-06-13; ships Hermes v0.15.x targeting — gh#102 CPU fix, gh#112 stderr surface, gh#105 menu-bar flash, plus the 2026-06-13 audit sweep). **Scarf `main` post-v2.10.3** now targets Hermes v0.16.0 (v2026.6.5) — v0.16 compatibility merged via PR #114/#115/#116 AFTER the v2.10.3 cut, so the v0.16 surface is on `main` but not yet in a released build. v0.15.0/.1/.2 remain fully supported; v0.15.1 was the hotfix wave (dashboard 401, Docker --insecure opt-in, MCP bare-command resolution, Kanban SIGTERM, skills.sh catalog, /yolo mid-session, /model parity); v0.15.2 was a packaging-only fix for plugin.yaml. #current
- [compatibility] Minimum supported Hermes: v0.6.0 (2026-03-30). All versions v0.6.0 through v0.16.0 are verified. Older Hermes versions degrade gracefully — new behavior is capability-gated. #minimum
- [v016-target] v0.16.0 (v2026.6.5) shipped upstream 2026-06-05 and is Scarf's current development target — see [[Hermes v0.16 Compatibility Decisions]]. Every v0.16 surface is capability-gated or schema-detected so older hosts render byte-identical. #status
- [schema] Scarf reads Hermes's SQLite state.db and parses CLI output from `hermes status`, `hermes doctor`, `hermes tools`, `hermes sessions`, `hermes gateway`, `hermes pairing`. Automatic schema detection provides backward compatibility (v0.16 adds the `messages.active` soft-delete column — first schema change since v0.11; detected via `hasMessagesActiveColumn`). #schema
- [parsing] Log lines may carry an optional `[session_id]` tag between level and logger name; `HermesLogService.parseLine` treats the session tag as an optional capture group so older untagged lines still parse. #logs
- [sync-checklist] On each Hermes bump, keep in sync: `overlayOnlyProviders` / `modelAliases` / `demotedProviders` / `imageGenModels` (vs hermes_cli/providers.py + models.py + xai_retirement.py), the platform roster (vs plugins/platforms/ + gateway/platforms/), and the search/TTS backend lists. #maintenance

## Relations
- implements [[Hermes Capability Gating Pattern]]
- supersedes [[Hermes v0.15 Capability Gating Decisions]]
