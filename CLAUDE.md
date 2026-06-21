# Scarf — macOS GUI for the Hermes AI Agent

## Build

```bash
xcodebuild -project scarf/scarf.xcodeproj -scheme scarf -configuration Debug build
```

<!-- memophant:begin -->
<!-- memophant:shim -->
> Agent instructions for this project live in [AGENTS.md](./AGENTS.md) — read it before
> starting work. Memophant manages a repo-resident memory system (`.memory/`, `wiki/`, `design/`,
> `code/`, `TASKS.md`) and a native MCP server (`memophant-mcp`) for read/write. Substance lives
> in those files, not here.
<!-- memophant:end -->
## Build & run a local copy

`./scripts/build-detached.sh` — no arguments. Builds into isolated DerivedData and launches a
decoupled, visually-distinct **dev copy** you can see; each run quits only the copy it launched
before (never other copies running elsewhere). Replaces the old `run-detached.sh`.
