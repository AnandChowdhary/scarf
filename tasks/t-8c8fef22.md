---
id: t-8c8fef22
title: gh#123: macOS remote dies until remove/re-add — stale ControlMaster recovery (wake observer + reactive -O exit on ACP connect failure)
status: done
added: 2026-07-12
---

## Description

Root-caused + fixed 2026-07-12, commit 155c83f on main (unreleased). Mechanism: ControlMaster's TCP dies (sleep/wake/network change) but the master lingers holding its socket; ControlMaster=auto routes every ssh through the corpse (10s hang each; ACP init blows its 60s budget) — the ONLY -O exit path was removeServer, hence "remove/re-add fixes it". Fix: SSHTransport.recoverControlMasterIfDead() (-O check → muxed probe → -O exit only if provably dead), called from ChatViewModel remote start-failure catches + before the reconnect loop, and from a new NSWorkspace.didWakeNotification observer in ServerLiveStatusRegistry (3s settle). gh#123 commented; keep issue open until released + reporter confirms.

## Plan



## Artifacts



