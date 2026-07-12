# Scarf v2.16.1

A focused connection-reliability patch, driven by two GitHub reports. The headline: **a remote server that "stops working after a while" now heals itself** — no more removing and re-adding the server to get it back ([#123](https://github.com/awizemann/scarf/issues/123)). Alongside it, the shared core learns to read Hermes configs that live **inside a Docker container** ([#112](https://github.com/awizemann/scarf/issues/112)), which lands in ScarfGo with the next TestFlight build.

## Remotes recover from dead SSH connections instead of hanging on them

Scarf multiplexes all of its ssh traffic to a server through one OpenSSH **ControlMaster** connection — that's what makes the bursty status and file reads cheap. But when the TCP session behind that master died (sleep/wake and network changes are the classic triggers), the master could linger holding its socket, and every subsequent ssh — the chat connect, the automatic reconnect attempts, the pollers — was routed through the corpse, each hanging for its full timeout until the chat sat permanently at the loading screen.

The kicker: the only code path that ever told a stale master to exit was **removing the server**, which is exactly why remove-and-re-add was the one reliable fix users found (and why quitting and relaunching usually didn't help — the socket lives outside the app).

Now:

- **Failure paths reset the transport.** A remote chat-start failure or a died stream probes the master and resets it if it's provably dead — so a plain retry, and the automatic reconnect loop, now do what remove-and-re-add did.
- **Wake recovery.** On wake from sleep, Scarf probes every registered server's master (after a short network-settle delay) and resets only the dead ones.

The probe is deliberately two-step — "does a master own the socket?" then a trivial multiplexed command — so a **healthy** connection is never dropped: an active chat shares the master's TCP session, and blindly resetting on wake would have killed it.

## Hermes in Docker: config reads fall back to the CLI

If Hermes runs inside a container, `~/.hermes/config.yaml` doesn't exist on the SSH host — it lives inside the container, visible only to the `hermes` wrapper. Writes always worked (they go through `hermes config set`, which the wrapper runs in-container), but every direct file read failed: Settings claimed *"config.yaml not found"*, and the chat preflight demanded a model choice on every start even though the config was fully set.

Config reads in the shared core now fall back through the Hermes CLI itself: first `cat "$(hermes config path)"` in the same wrapper shell the writes use (covers `HERMES_HOME` overrides and bind-mounted container homes), then a `hermes config show` probe — the one read that runs *inside* the container — which recovers your configured model and provider. The chat preflight passes, and Settings populates its model section and, instead of the misleading "not found", explains the container topology and teaches the actual fix: bind-mount the container's Hermes home to `~/.hermes` on the host, which unlocks everything else (full Settings, memory files, and the Dashboard's `state.db` reads).

These surfaces are ScarfGo's, so this fix ships to devices with the **next TestFlight build** — the Mac app benefits automatically anywhere the shared reader is adopted next.

## Under the hood

- New `HermesConfigReader` (ScarfCore) with unit tests against the real Hermes v0.17 `config show` output; the fallback chain is remote-only by design, so a local "file missing" stays missing.
- Test contexts that fake a remote Hermes are now hermetic — the CLI fallbacks can no longer accidentally find the development machine's real Hermes install. 805/805 ScarfCore tests green.

## Upgrade notes

- **Sparkle** will offer the update automatically, or use **Scarf → Check for Updates**. macOS 14.6+ deployment target unchanged.
- **iOS / ScarfGo:** the Docker config-read fallback ships with the next TestFlight build; [#112](https://github.com/awizemann/scarf/issues/112) stays open as its tracker until then. The #123 self-healing applies to the Mac app's ssh transport (ScarfGo's Citadel transport pools connections since v2.12 and is unaffected).
