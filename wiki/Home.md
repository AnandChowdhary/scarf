---
title: Home
type: note
permalink: scarf-wiki/home
---

# Scarf

A native macOS companion app for the [Hermes AI agent](https://github.com/hermes-ai/hermes-agent). Full visibility into what Hermes is doing, when, and what it creates — across one local install or many remote ones.

**Latest release:** [v2.15.1](https://github.com/awizemann/scarf/releases/tag/v2.15.1) — a focused patch for **aggregator providers**: the chat preflight no longer raises a false "Model/provider mismatch" banner on valid OpenRouter / OpenCode / KiloCode / Hugging Face / NovitaAI configs (the slash in `xiaomi/mimo-v2.5` is the model's namespace, not a provider prefix — and both one-click "fixes" would have broken a working `config.yaml`, [#121](https://github.com/awizemann/scarf/issues/121)). The banner's fix buttons are now alias-aware and validated against the provider catalog so they can never write a provider Hermes doesn't have. See [v2.15.1 release notes](https://github.com/awizemann/scarf/blob/main/releases/v2.15.1/RELEASE_NOTES.md).

**Previous release:** [v2.15.0](https://github.com/awizemann/scarf/releases/tag/v2.15.0) — **Projects grow up** (skips 2.14; a feature release, not a Hermes-compat one), the biggest Projects update since v2.3. A project becomes a first-class object with its own **cockpit** — one pane for Dashboard, Sessions, Board, Site, Context, Cron, Memory, Secrets, Templates, Slash, Mini-apps, and Fleet — and gains three powers: **[Mini-apps](Mini-Apps)** (sandboxed web panels that drive the agent through a versioned `window.scarf` bridge, in a locked-down `WKWebView` with default-deny permissions reviewed on first open and an isolated rate-limited agent session), **[Fleet & Portfolio](Fleet-&-Portfolio)** (the same repo across multiple hosts grouped as one logical project, with drift surfaced and **Apply to Fleet** to push model preset / board / cron), and **one-click Upgrade Project** (a fast structural pass then an agent hand-off that tailors a dashboard, slash commands, cron, and a starter mini-app). **Project chats now load your `AGENTS.md`** automatically (treat a project's context files like its code — only open chats in projects you trust), plus SSH-path command-injection hardening and a window-frame persistence fix. See [v2.15.0 release notes](https://github.com/awizemann/scarf/blob/main/releases/v2.15.0/RELEASE_NOTES.md).

**Earlier release:** [v2.13.0](https://github.com/awizemann/scarf/releases/tag/v2.13.0) — ScarfGo (iOS) gains **Hermes profile switching** (per-connection scoping that never touches the host's `active_profile`) plus an iOS remote-chat/Settings reliability fix (one pooled SSH connection per server instead of one per read). The Skills "What's New" pill now keys its baseline per (server, profile). See [v2.13.0 release notes](https://github.com/awizemann/scarf/blob/main/releases/v2.13.0/RELEASE_NOTES.md).

**Earlier release:** [v2.12.0](https://github.com/awizemann/scarf/releases/tag/v2.12.0) — coordinated catch-up to **Hermes v0.17.0** (the largest Hermes release yet, though Scarf needed only a focused slice), bundled with a **remote-chat performance fix**: typing into a session on an SSH host no longer lags or spikes CPU now that watcher-driven reads run off the main thread ([#119](https://github.com/awizemann/scarf/issues/119)). The v0.17 audit found the upstream surface entirely stable (zero mandatory changes), so it's a feature catch-up plus pre-existing-bug fixes — four broken Health/Settings CLI actions and the Curator "Prune" rebuilt as the reversible **"Archive idle skills"** — alongside new **WhatsApp Business Cloud API** + **SimpleX** gateway setup forms, Telegram rich-messages / status toggles, an opt-in curator-consolidation toggle, and a max-concurrent-sessions cap, all capability-gated (pre-v0.17 hosts render the v2.11.0 surface byte-identical). v2.11.0 before it caught up to **Hermes v0.16.0** (the `messages.active` soft-delete filter on `/undo`, live ACP session titles, a `rewind_count` badge). See [v2.12.0 release notes](https://github.com/awizemann/scarf/blob/main/releases/v2.12.0/RELEASE_NOTES.md) and the full [Release Notes Index](Release-Notes-Index) for everything earlier.
**Latest mobile:** [Join the public TestFlight](https://testflight.apple.com/join/qCrRpcTz). The link is live now but only accepts new beta testers once Apple's Beta Review approves the first build — see [ScarfGo](ScarfGo) for the full feature tour.
**Targets Hermes:** v0.17.0 (v2026.6.19) — the v0.17 audit found the upstream surface (state.db schema, ACP wire protocol, CLI verbs, config keys, model catalog) entirely stable, so Scarf's v0.17 support (shipped in v2.12.0) is a feature catch-up: WhatsApp Business Cloud API + SimpleX gateway setup forms, Telegram rich-messages / online-offline status toggles, an opt-in curator-consolidation toggle, and a max-concurrent-sessions cap — layered on the v0.16 wave from v2.11.0 (the `messages.active` soft-delete filter, live ACP session titles, the `rewind_count` badge). v2.15.0 itself is a Projects feature release and does not change the Hermes target. v0.16 / v0.15 / v0.14 / v0.13 / v0.12 / v0.11 / v0.10 still work for everything that didn't change — Scarf detects the host's Hermes version and hides newer-only surfaces gracefully.
**Available in:** English, Simplified Chinese (zh-Hans), German (de), French (fr), Spanish (es), Japanese (ja), Brazilian Portuguese (pt-BR). See [Localization](Localization). _ScarfGo is English-only in v1._

## Quick links

- [Installation](Installation) — download, first launch, system requirements (Mac)
- **[ScarfGo](ScarfGo)** — the iPhone companion (public TestFlight from v2.5)
- **[ScarfGo Onboarding](ScarfGo-Onboarding)** — SSH keys, paste-public-key, connection test
- [Platform Differences](Platform-Differences) — Mac vs iOS feature matrix
- [First Run](First-Run) — what Scarf expects in `~/.hermes/`
- [Project Templates](Project-Templates) — `.scarftemplate` bundles, install / export / author
- **[Slash Commands](Slash-Commands)** — author project-scoped slash commands (v2.5+)
- **[Hermes Proxy](Hermes-Proxy)** — OpenAI-compatible local server for Codex / Aider / Cline / VS Code Continue (v2.9+, Hermes v0.14+)
- **[Design System](Design-System)** — ScarfColor / ScarfFont / components reference
- [Architecture Overview](Architecture-Overview) — MVVM-F, services, transport, ScarfCore
- [Performance Monitoring](Performance-Monitoring) — ScarfMon: opt-in perf instrumentation, how to capture a baseline
- [Servers & Remote](Servers-and-Remote) — adding remote Hermes hosts over SSH
- [Localization](Localization) — supported languages + how to contribute a new one
- [Release Notes Index](Release-Notes-Index) — every version's notes
- [Troubleshooting: Update "improperly signed"](Troubleshooting-Sparkle-Update) — recovery if Sparkle rejects an update
- [Privacy Policy](Privacy-Policy) · [Support](Support) — what data the apps access; how to get help
- [Wiki Maintenance](Wiki-Maintenance) — how this wiki is edited and kept in sync

## What Scarf does

Scarf mirrors Hermes's surface area through a sidebar-based UI grouped into four sections:

- **Monitor** — Dashboard, Insights, Sessions, Activity. See what Hermes is doing.
- **Interact** — Chat, Memory, Skills. Talk to Hermes and shape what it knows.
- **Configure** — Platforms, Personalities, Quick Commands, Credential Pools, Plugins, Webhooks, Profiles, Servers. Set Hermes up.
- **Manage** — Tools, MCP Servers, Gateway, Cron, Health, Logs, Settings. Operate Hermes.

Scarf 2.0 is a multi-window app — one window per Hermes server, local or remote. Remote hosts are reached over plain SSH using your existing `~/.ssh/config`, agent, ProxyJump, and ControlMaster.

## Project status

Open-source (MIT), 160+ stars, actively maintained. See [Roadmap](Roadmap) for what's coming.

---
_Last updated: 2026-07-04 — Scarf v2.15.1 (aggregator-provider mismatch-banner patch, #121; provider tables now gated by scripts/check-hermes-tables.py)._