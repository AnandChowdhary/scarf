---
id: t-af0690ff
title: Cut v2.15.0 — Projects Grow Up (mini-apps, fleet, upgrade, cockpit)
status: done
added: 2026-06-28
priority: high
---

## Description

Feature release v2.15.0 (skips 2.14; not a Hermes-compat release). Scope = everything since v2.13.0 (the "Projects Grow Up" arc): first-class ScarfProject object, mini-apps (sandboxed web UIs + window.scarf bridge + scarf.prompt/onEvent agent channel + permission gate), Fleet/Portfolio (drift + apply-to-fleet, capability-gated cron copy), one-click Upgrade Project, cockpit single-pane, project chats load AGENTS.md (+ trust-awareness line t-cea43144), plus hardening (SSH path injection, window-frame persistence).

Prep deliverables (this session): releases/v2.15.0/RELEASE_NOTES.md, README "What's New in 2.15.0", wiki (new Mini-Apps + Fleet-and-Portfolio pages, Projects-and-Profiles/Chat updates, Release-Notes-Index, Home latest-release, sidebar), documents/plans runbook, build-verify (Release compile + ScarfCore & scarfTests), clean tree on main, delete merged branches (feat/projects, fix/miniapp-agent-cwd-docstring-t0b850b5b), keep gh-pages worktree.

Hand-off: maintainer runs ./scripts/release.sh 2.15.0 (bumps 2.13.0->2.15.0 + build 46->47, archives Universal+ARM64, notarizes, EdDSA-signs appcast, pushes main+tag, GH release). Do NOT bump MARKETING_VERSION manually (flips script to resume mode). Do NOT push.

## Plan



## Artifacts



