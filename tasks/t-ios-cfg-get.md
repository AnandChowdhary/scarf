---
id: t-ios-cfg-get
title: iOS Settings: route config reads through the Hermes CLI wrapper for Docker hosts (config dir is in-container)
status: done
added: 2026-06-06
source: gh#112 failure 2
---

## Description

DONE 2026-07-12, commit 5dc1c55 on main (unreleased). Implemented per the corrected plan: HermesConfigReader (ScarfCore, remote-only) — (1) direct read, (2) cat "$(hermes config path)" in ONE wrapper shell (covers HERMES_HOME overrides + bind-mounted homes), (3) hermes config show Model-line probe (Python-dict repr, per-key regex, either quote style) synthesizing a minimal model config — the only read that works for pure in-container Docker; enough to pass the chat preflight gate. Wired into IOSSettingsViewModel.load (with container-topology guidance message + bind-mount recipe) and iOS ChatView.passModelPreflight. Unit tests against real v0.17 config show output; M5 fake-hermes contexts got hermesBinaryHint=/nonexistent for hermeticity. Residual (needs bind mount, no code path possible): raw YAML view, memory files, state.db/Dashboard for in-container installs.

## Plan

CORRECTION (2026-06-25, verified against hermes v0.16 locally): there is NO `hermes config get`. The `config` subcommands are: show / edit / set / path / env-path / check / migrate. The original "mirror `config set` with `config get`" framing can't work as written.

What v0.16 actually offers for reads:
- `hermes config show` — human-formatted box (Paths / API Keys / Model / …). NO `--json`; does NOT accept a key arg (`config show model.provider` errors out to top-level usage). The Model line is a Python-dict repr: `{'provider': 'custom:x', 'default': 'y'}`. Parseable but brittle.
- `hermes config path` / `config env-path` — print the resolved config.yaml / .env paths; for the docker wrapper these resolve INSIDE the container.

Options for F2 (decide at implementation; RE-VERIFY against the live target version — reporter was on v0.17, may add `--json`/`get`):
1. Read the real file through the SAME wrapper the writes use: `cat "$(hermes config path)"` over the transport. Works for docker (path + cat both run in-container via the wrapper) and native; yields the structured YAML we already parse with HermesConfig. CLEANEST.
2. Parse `hermes config show`. Avoid — human format, no --json, fragile.

Recommendation: option 1. Keep the existing SFTP fast-path for native hosts; fall back to the wrapper read (`cat $(hermes config path)`) when the SFTP read finds nothing — that's the Docker case (config inside the container, invisible to host SFTP). See [[ios-transport-must-be-pooled-per-serverid-sshconfig-un]] for the related transport work and [[t-1fef0a83]] for the gh#112 write-path fix.

## Artifacts



