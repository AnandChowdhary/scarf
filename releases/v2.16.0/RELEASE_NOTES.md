# Scarf v2.16.0

**Scarf now targets the Hermes v0.18 line — audited against v0.18.0 (v2026.7.1) and re-audited against the v0.18.1/v0.18.2 patches (v2026.7.7.2).** The headline is invisible when it works: Hermes v0.18 introduced **in-place session compaction**, which soft-archives the messages it summarizes away — and Scarf's message search now stays in perfect lockstep with Hermes on those sessions instead of silently hiding the archived rows. The two release audits also surfaced long-standing Scarf bugs, now fixed: the **Web Tools settings tab had never actually worked** (it wrote config keys Hermes doesn't read), and **editing a cron job from ScarfGo could silently strip scheduler state from jobs.json** — including repeat counts and tool restrictions. Every v0.18 surface degrades gracefully — older Hermes hosts render exactly as before.

## Search keeps up with Hermes v0.18 compaction

Hermes v0.18 can compact a long session **in place**: the old messages are summarized, marked `compacted`, and replaced by a fresh active set — but they remain discoverable through Hermes's own search. Scarf's search filtered strictly to active messages, so on a compacted session Scarf and `hermes` would return **different results for the same query on the same database**.

Scarf now detects the new `messages.compacted` column (the first `state.db` schema change since v0.16) and widens search to include compacted rows, exactly matching Hermes's semantics. The distinction that matters: rows you deliberately removed with `/undo` stay hidden everywhere, compacted rows stay findable in search — and neither ever resurfaces in the chat transcript, which shows only the live conversation, same as Hermes. On pre-v0.18 databases the column doesn't exist and nothing changes.

## The Web Tools tab works now (it never did)

An embarrassing one, caught by the v0.18 source audit: Scarf's Web Tools settings wrote `web_tools.backend`-style keys into `config.yaml`, but Hermes reads the `web:` block (`web.backend`, `web.search_backend`, `web.extract_backend`) — and has since at least v0.9. Because `hermes config set` accepts any key without complaint, every save "succeeded," wrote a block nothing reads, and the tab read that same dead block back — a perfectly self-consistent illusion. If you ever picked a search or extract backend in Scarf and wondered why nothing changed: that's why.

Both sides now use the real keys. An empty selection means what it means in Hermes: fall back to the shared backend, then auto-detect from your API keys. Any stale `web_tools:` block left in your `config.yaml` is inert and safe to delete or ignore — Scarf deliberately does **not** auto-migrate its values, since they were never in effect and silently activating an old choice could change a working setup.

## Cron jobs round-trip losslessly — the whole bug class is gone

Toggling a cron job's enabled switch in ScarfGo — or saving any edit in the cron editor — rebuilt the job from Scarf's model and dropped everything the model didn't know about. The v0.18.0 audit caught three such fields (`workdir`, `context_from`, `no_agent`); the v0.18.2 re-audit went deeper and found the model was missing **over a dozen more** that Hermes persists: `repeat` counts (a "run 5 times" job silently became "run forever"), `enabled_toolsets` (a per-job tool restriction), per-job `provider`/`base_url` routing, creation metadata, and the v0.18.2 scheduler's new `run_claim` double-execution guard.

Rather than add fields forever, Scarf now preserves **every key it doesn't model** through the decode → edit → encode cycle, so a future Hermes can add job fields and ScarfGo edits will never strip them again. The audit also found two keys that had *never* matched Hermes's spelling — the pre-run script is stored as `script` (not `pre_run_script`) and cron expressions as `expr` with interval `minutes` — so those now read and write the real keys. Verified against a live jobs.json: byte-equivalent round-trip through the toggle path.

## No more false "model/provider mismatch" on custom endpoints

v2.15.1 stopped the mismatch banner from misfiring on aggregator providers like OpenRouter (GH #121). The same courtesy now extends to **custom endpoints**: if your provider is `custom` or `custom:<name>` (a self-hosted vLLM, a LAN gateway), a slash in the model ID is your server's namespace, not a stale provider prefix — Hermes itself treats `custom:*` as an aggregator and never second-guesses those configs, and now neither does Scarf.

## Providers: Mixture of Agents in, Vertex AI replaces Gemini CLI

- **MoA (Mixture of Agents)** — Hermes v0.18's virtual provider that fans a prompt out to multiple advisor models and aggregates their answers — now appears in Scarf's model picker. It needs no credentials; its "models" are preset names.
- **Google Vertex AI** (`vertex`) replaces the removed `google-gemini-cli` OAuth provider upstream — Gemini via GCP with service-account or ADC auth. It's catalog-backed, so it surfaces in the picker automatically; the retired Gemini CLI entry and its aliases are gone.

## Under the hood

- The full v0.18 audit ran across eight integration surfaces against the tagged Hermes source: the ACP wire protocol, all 42+ CLI invocations Scarf makes, the config keys Scarf writes, and the gateway platform roster are verified byte-stable — zero changes needed. The provider tables pass the mechanical `check-hermes-tables.py` gate against the exact `v2026.7.1` tag.
- The v0.18.1/v0.18.2 patches (a ~712-commit rollup) were re-audited surface-by-surface against `v2026.7.7.2`: the ACP wire, CLI argparse, provider tables, gateway platforms, MCP/skills/curator, and every state.db column Scarf queries are unchanged — the cron `run_claim` field above was the only integration-facing addition. Hermes's new `sessions.display_name` and `hermes curator usage` are noted as future Scarf surfaces.
- New capability flags (`hasCronAttachToSession`, `hasMCPReauth`, `isV018OrLater`) with the standard degradation test cluster; the compacted-column handling is schema-detected, not version-gated, so it follows the database you're actually connected to.
- New Hermes v0.18 verbs noted for future Scarf surfaces: `hermes serve` (headless backend), `hermes journey` (learning timeline), `hermes mcp reauth` (refresh expired MCP OAuth tokens).
- 18 new tests: search widening + transcript narrowing on compacted DBs, cron field round-trips (including a full v0.18.2-shaped job and legacy-key migration), v0.18 capability degradation, MoA credential-gate routing, and custom-endpoint preflight skips. 799/799 ScarfCore tests green.

## Upgrade notes

- **Sparkle** will offer the update automatically, or use **Scarf → Check for Updates**. macOS 14.6+ deployment target unchanged. No action needed on upgrade: the compacted-search behavior activates only against v0.18 databases, and your first Web Tools save writes the correct keys.
- If you had configured Web Tools backends in Scarf before, re-pick them once — the old values never reached Hermes, so Scarf now shows the true (likely unset) state.
- **iOS / ScarfGo:** the cron field-loss fix applies to the iOS cron editor and ships with the next TestFlight build, alongside the v2.15.0 project-context fix.
