# Scarf v2.15.1

**The model/provider mismatch banner learned how OpenRouter works.** If your Hermes is configured with an aggregator provider — OpenRouter, OpenCode, KiloCode, Hugging Face, NovitaAI — Scarf's chat preflight could flag a perfectly valid config as a "Model/provider mismatch" and offer two one-click fixes that would each have **broken** it ([#121](https://github.com/awizemann/scarf/issues/121)). That false alarm is gone, and the banner's fix buttons are now validated so they can never write a provider Hermes doesn't have. Thanks to **@rmichelena** for the sharp report.

## The mismatch banner and aggregator providers

The banner exists for a real failure: switching providers via Credential Pools could leave the old provider's prefixed model stranded in `model.default` (say `anthropic/claude-…` with `model.provider: nous`), and chats would die at first prompt with an opaque `-32603` error. The check caught that by treating anything before a `/` in `model.default` as a provider prefix.

But for **aggregator** providers, the slash is part of the model's own name — OpenRouter's `xiaomi/mimo-v2.5` is `org/model`, not `provider/model`. Hermes models this distinction explicitly (`is_aggregator` in its provider table); Scarf's check didn't, so a working OpenRouter config raised the banner, and both offered fixes ("use `xiaomi`" / "strip the prefix") would have corrupted `config.yaml`. The preflight now skips the mismatch check entirely when `model.provider` resolves to an aggregator — including Hermes's bare-`openai` → OpenRouter alias.

The original protection is untouched: a genuinely stale prefix under a direct provider still raises the banner with the same one-click fixes.

## The fix buttons can no longer write a broken provider

Two more hardening passes on the same banner:

- **Alias-aware comparison.** Hermes accepts many provider spellings (`claude` ↔ `anthropic`, `x-ai` ↔ `xai`, `zhipu` ↔ `zai`, …). Scarf now mirrors Hermes's full alias table and canonicalizes both sides before comparing, so an alias-equivalent prefix no longer reads as a mismatch.
- **Unknown prefixes are contained.** If `model.default` carries a prefix that isn't any provider Hermes knows, the banner still warns (that config really will fail) — but the "Use *prefix*" button is hidden rather than offering to write a nonexistent provider into `config.yaml`, and the banner explains the likely aggregator intent. The provider roster comes from the models.dev catalog and is only consulted on the rare mismatch path, so remote (SSH) servers pay nothing on normal refreshes.

## Under the hood

- Scarf hand-mirrors three provider tables out of Hermes's source; a new `scripts/check-hermes-tables.py` now diffs all three against `hermes_cli/providers.py` mechanically and fails loudly on drift, replacing the eyeball reconciliation on every Hermes bump. All tables verified against the exact Hermes v0.16.0 (`v2026.6.5`) tag Scarf targets.
- Dormant provider-overlay entries (`lmstudio`, `tencent-tokenhub` — since absorbed by models.dev) are annotated as deliberate stale-cache fallback so the checker's warnings read as policy, not drift.
- 11 new `ModelPreflight` tests pin the aggregator skip, alias equivalence, unknown-prefix containment, and the original stale-prefix regression guard.

## Upgrade notes

- **Sparkle** will offer the update automatically, or use **Scarf → Check for Updates**. macOS 14.6+ deployment target unchanged. No data migrations, and no config changes — if you saw the false banner on an aggregator config, it simply disappears; nothing to reconcile.
- **iOS / ScarfGo:** this is a Mac-track release. Also on main since v2.15.0: ScarfGo project chats now load the full project context (AGENTS.md, cron, config, template) — that fix rides the next TestFlight build.
