# Scarf v2.16.0

**Scarf now targets Hermes v0.18.0 (v2026.7.1).** The headline is invisible when it works: Hermes v0.18 introduced **in-place session compaction**, which soft-archives the messages it summarizes away — and Scarf's message search now stays in perfect lockstep with Hermes on those sessions instead of silently hiding the archived rows. The same release audit surfaced two long-standing Scarf bugs that are now fixed: the **Web Tools settings tab had never actually worked** (it wrote config keys Hermes doesn't read), and toggling a cron job on iOS could **permanently strip fields from jobs.json**. Every v0.18 surface degrades gracefully — older Hermes hosts render exactly as before.

## Search keeps up with Hermes v0.18 compaction

Hermes v0.18 can compact a long session **in place**: the old messages are summarized, marked `compacted`, and replaced by a fresh active set — but they remain discoverable through Hermes's own search. Scarf's search filtered strictly to active messages, so on a compacted session Scarf and `hermes` would return **different results for the same query on the same database**.

Scarf now detects the new `messages.compacted` column (the first `state.db` schema change since v0.16) and widens search to include compacted rows, exactly matching Hermes's semantics. The distinction that matters: rows you deliberately removed with `/undo` stay hidden everywhere, compacted rows stay findable in search — and neither ever resurfaces in the chat transcript, which shows only the live conversation, same as Hermes. On pre-v0.18 databases the column doesn't exist and nothing changes.

## The Web Tools tab works now (it never did)

An embarrassing one, caught by the v0.18 source audit: Scarf's Web Tools settings wrote `web_tools.backend`-style keys into `config.yaml`, but Hermes reads the `web:` block (`web.backend`, `web.search_backend`, `web.extract_backend`) — and has since at least v0.9. Because `hermes config set` accepts any key without complaint, every save "succeeded," wrote a block nothing reads, and the tab read that same dead block back — a perfectly self-consistent illusion. If you ever picked a search or extract backend in Scarf and wondered why nothing changed: that's why.

Both sides now use the real keys. An empty selection means what it means in Hermes: fall back to the shared backend, then auto-detect from your API keys. Any stale `web_tools:` block left in your `config.yaml` is inert and safe to delete or ignore — Scarf deliberately does **not** auto-migrate its values, since they were never in effect and silently activating an old choice could change a working setup.

## Cron jobs no longer lose fields on toggle or edit

Toggling a cron job's enabled switch in ScarfGo — or saving any edit in the cron editor — rebuilt the job while dropping the fields the UI didn't know about: `workdir` (project context), `context_from` (job chaining), and `no_agent` (script-only watchdog mode). The next save wrote the truncated job to `jobs.json`, permanently. Both paths now round-trip every field, including v0.18's new per-job `attach_to_session` (mirror a job's delivery into its chat session), which Scarf preserves even though it has no editor UI for it yet.

## Providers: Mixture of Agents in, Vertex AI replaces Gemini CLI

- **MoA (Mixture of Agents)** — Hermes v0.18's virtual provider that fans a prompt out to multiple advisor models and aggregates their answers — now appears in Scarf's model picker. It needs no credentials; its "models" are preset names.
- **Google Vertex AI** (`vertex`) replaces the removed `google-gemini-cli` OAuth provider upstream — Gemini via GCP with service-account or ADC auth. It's catalog-backed, so it surfaces in the picker automatically; the retired Gemini CLI entry and its aliases are gone.

## Under the hood

- The full v0.18 audit ran across eight integration surfaces against the tagged Hermes source: the ACP wire protocol, all 42+ CLI invocations Scarf makes, the config keys Scarf writes, and the gateway platform roster are verified byte-stable — zero changes needed. The provider tables pass the mechanical `check-hermes-tables.py` gate against the exact `v2026.7.1` tag.
- New capability flags (`hasCronAttachToSession`, `hasMCPReauth`, `isV018OrLater`) with the standard degradation test cluster; the compacted-column handling is schema-detected, not version-gated, so it follows the database you're actually connected to.
- New Hermes v0.18 verbs noted for future Scarf surfaces: `hermes serve` (headless backend), `hermes journey` (learning timeline), `hermes mcp reauth` (refresh expired MCP OAuth tokens).
- 15 new tests: search widening + transcript narrowing on compacted DBs, cron field round-trips, v0.18 capability degradation, and MoA credential-gate routing. 796/796 ScarfCore tests green.

## Upgrade notes

- **Sparkle** will offer the update automatically, or use **Scarf → Check for Updates**. macOS 14.6+ deployment target unchanged. No action needed on upgrade: the compacted-search behavior activates only against v0.18 databases, and your first Web Tools save writes the correct keys.
- If you had configured Web Tools backends in Scarf before, re-pick them once — the old values never reached Hermes, so Scarf now shows the true (likely unset) state.
- **iOS / ScarfGo:** the cron field-loss fix applies to the iOS cron editor and ships with the next TestFlight build, alongside the v2.15.0 project-context fix.
