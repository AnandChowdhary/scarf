---
id: t-848d3adc
title: Fleet cron-copy: faithfully copy no_agent/pre_run_script jobs (replicate the script file to the target)
status: ideas
added: 2026-06-28
priority: low
---

## Description

**RECOMMENDATION (assessed 2026-06-28): DEFER indefinitely — build only on demand.** Niche: only helps users who keep script-only watchdog (`no_agent`) cron jobs in a project AND want them fleet-replicated — a narrow intersection. The current behavior (skip + surface "N script-only skipped", shipped in t-69ccb849) is honest and safe — no broken no-ops. A faithful copy requires cross-transport script-FILE replication (read source `pre_run_script` → write to target, path-rewritten, dir-created) — real work for a rare pattern. Don't build unless a user actually hits the wall.

---

Surfaced by the t-69ccb849 fresh-eyes audit (2026-06-28). FleetApplyExecutor.applyCron now SKIPS `no_agent` (script-only watchdog) `[proj:]` cron jobs with a surfaced "N script-only skipped" message — because a faithful copy needs the pre-run script FILE replicated to the target, which fleet-apply doesn't do. Before this, such jobs were silently created as empty-prompt no-ops reported as "created". (Verified: `HermesCronJob.preRunScript` is a host-local script PATH — CronView "Script path" field, "Python script whose stdout is injected".)

To faithfully copy a no_agent job: (1) read the source `pre_run_script` file via the source transport, (2) write it to an equivalent path on the target transport (path-rewritten source→target root, dir-created), (3) forward `--script <rewritten path>` + `--no-agent` (gated on target caps.hasCronNoAgent v0.13+; pre-v0.13 target can't run no-agent → keep skipping). Also covers the lesser case: an AGENT job that ALSO carries a pre_run_script is currently copied WITHOUT the script (degraded-but-functional, keeps its prompt) — same script-replication mechanism would restore it. Scope this as a deliberate "replicate cron script assets across the fleet" feature, not a one-liner. Pairs with t-69ccb849.

## Plan



## Artifacts



