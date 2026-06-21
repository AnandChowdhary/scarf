---
name: scarf-miniapp-author
description: Author a Scarf mini-app — a small sandboxed web surface (HTML/CSS/JS) that renders inside a project's cockpit and talks to the bound Hermes session + project data through the versioned window.scarf bridge. Use to build a bespoke panel (a task board, an approval queue, a chart, a data table) for a project.
version: 1.0.0
author: Alan Wizemann
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [Scarf, mini-app, webview, bridge, cockpit, authoring]
    homepage: https://github.com/awizemann/scarf/wiki/Mini-Apps
prerequisites:
  commands: [hermes]
---

# Scarf Mini-App Author

Build a **mini-app**: a small web surface (HTML/CSS/JS) that Scarf renders *inside* a project's cockpit (the "Mini-apps" panel) over a narrow, versioned JS bridge (`window.scarf`). A mini-app is a project facet — it lives in the project directory and is bound to the project (and, for `scarf.prompt`, a dedicated Hermes agent session). Because it's plain web + a tiny API, you can author one reliably with your file tools.

## When to invoke this skill

- *"Build me a mini-app that …"* / *"Add a little app to this project for …"*
- *"Make a panel that shows / lets me …"* (a task list, an approval queue, a status board, a chart, a form).
- During a **project upgrade** (the `scarf-template-author` upgrade flow), to add a starter mini-app or two.

Do **not** invoke for: editing the project's `dashboard.json` (that's the Dashboard panel — use widgets), or pure reference questions (answer inline from below).

## Where a mini-app lives

```
<project>/.scarf/miniapps/<id>/
├── miniapp.json     # manifest (REQUIRED)
├── index.html       # entry document (REQUIRED; default entry name)
└── …                # any local CSS/JS/images, referenced by RELATIVE path
```

- `<id>` is the **directory name** and is canonical — it must equal `miniapp.json.id`. Use a short kebab-case slug (e.g. `task-board`).
- Scarf discovers the mini-app automatically once the dir + `miniapp.json` exist; no registration step.

## The manifest — `miniapp.json`

```json
{
  "id": "task-board",
  "name": "Task Board",
  "version": "1.0.0",
  "entry": "index.html",
  "minBridgeVersion": "1.0",
  "permissions": ["query:kanban.tasks"],
  "panelHint": { "preferredWidth": 480, "placement": "panel" },
  "generated": true
}
```

- Only `id` + `name` are required; `entry` defaults to `index.html`, `permissions` to `[]` (default-deny), `minBridgeVersion` to `"1.0"`, `generated` to `false`.
- **Set `"generated": true`** for anything you author — it marks the app as agent-written, which forces stricter permission defaults (see below). This is the honest + safe flag.
- `permissions` must list every bridge surface the app uses (default-deny — an undeclared call is refused).

## The bridge — `window.scarf` (injected at document start; current version `1.0`)

`scarf.context` and `scarf.version` are **synchronous** (baked in at load). Everything else is **async** (returns a Promise). Each async call is permission-checked host-side; a missing permission rejects.

| Call | Permission needed | Sensitive?† | Returns |
|---|---|---|---|
| `scarf.version` | — | — | `"1.0"` (string) |
| `scarf.context` | — | — | frozen `{ projectId, projectName, projectRoot, serverId, miniAppId, generated, bridgeVersion }` |
| `scarf.ui.toast(msg)` | — | — | shows a host toast |
| `scarf.ui.setTitle(title)` | — | — | sets the panel title |
| `scarf.ui.resize(w, h)` | — | — | layout hint |
| `scarf.ui.requestClose()` | — | — | asks the host to close the app |
| `scarf.store.get(key)` / `scarf.store.set(key, value)` | `store` | no | per-(project, mini-app) persisted KV (JSON values); `get` → value or `null`, `set` → `true` |
| `scarf.query(kind)` | `query:<kind>` | no | rows for `kind` as a JSON array. Implemented: `"kanban.tasks"`; any other kind replies `not_implemented`. (A 2nd `params` argument is accepted but **reserved — ignored in v1**.) |
| `scarf.kanban.read()` | `query:kanban.tasks` | no | array of the project's Kanban tasks (tenant-scoped); `[]` if none |
| `scarf.file.read(path)` | `file:read` | no | UTF-8 contents of a project file (path is **relative to the project root**, read-only, ≤4 MB, contained — no escaping the project) |
| `scarf.prompt(text, opts?)` | `prompt` | **yes** | sends a prompt to the project's bound agent session → resolves to the agent's final text (string); stream incremental output via `scarf.onEvent` |
| `scarf.onEvent(cb)` | `events` | no | `cb(ev)` fires for streamed agent events (message chunks, tool calls, completion) — pair with `prompt` |

† **Sensitive permissions** (`prompt`, `net`, `file:write`, `kanban:write`) default to **OFF** for `generated: true` apps until the user explicitly grants them in the permission sheet. Non-sensitive ones (`store`, `query:kanban.tasks`, `file:read`, `events`) default ON — note only the allow-listed `query:kanban.tasks` is non-sensitive (any other `query:<kind>` would be treated as sensitive, though none is implemented yet). **Prefer non-sensitive surfaces** so your app works immediately; only request `prompt` (and friends) when the app genuinely needs to drive the agent, and tell the user they'll be asked to grant it.

`net`, `file:write`, and `kanban:write` (move/create) are **not wired in this build** — don't rely on them. There is no external network: CSP blocks it and there's no `net` surface, so **bundle everything locally** (inline CSS/JS or local files; no CDNs, no `fetch()` to the internet).

## Hard rules (the sandbox)

1. **Self-contained.** Assets load over the `scarf-miniapp://` scheme scoped to the app dir. Reference local files by **relative path** (`./app.js`). No `file://`, no remote URLs, no external scripts/styles.
2. **Declare every permission** you use in `miniapp.json.permissions`, or the call is denied.
3. **Never assume secrets/config/filesystem-at-large.** The bridge cannot reach `~/.hermes`, `config.yaml`, `auth.json`, env, or tools — by design.
4. **Degrade gracefully.** Check `scarf.version` if you need a newer bridge; handle empty/permission-denied results without crashing the UI.
5. Keep it small and legible — a single `index.html` with inline `<style>`/`<script>` is ideal for a starter.

## Minimal working example — a Kanban task board

Needs only the non-sensitive `query:kanban.tasks` permission, so it runs immediately as a generated app.

`miniapp.json`:
```json
{ "id": "task-board", "name": "Task Board", "version": "1.0.0",
  "entry": "index.html", "minBridgeVersion": "1.0",
  "permissions": ["query:kanban.tasks"], "generated": true }
```

`index.html`:
```html
<!doctype html>
<html><head><meta charset="utf-8" />
<style>
  body { font: 13px -apple-system, sans-serif; margin: 0; padding: 12px; color: #1d1d1f; }
  h1 { font-size: 15px; margin: 0 0 10px; }
  .task { padding: 8px 10px; border: 1px solid #e3e3e6; border-radius: 8px; margin-bottom: 6px; }
  .status { font-size: 11px; color: #6e6e73; }
  .empty { color: #6e6e73; }
</style></head>
<body>
  <h1 id="title">Tasks</h1>
  <div id="list"><p class="empty">Loading…</p></div>
  <script>
    (async function () {
      document.getElementById("title").textContent = scarf.context.projectName + " — Tasks";
      scarf.ui.setTitle("Task Board");
      const list = document.getElementById("list");
      try {
        const tasks = await scarf.kanban.read();           // [] if none
        if (!tasks.length) { list.innerHTML = '<p class="empty">No tasks yet.</p>'; return; }
        list.innerHTML = "";
        for (const t of tasks) {
          const el = document.createElement("div");
          el.className = "task";
          // textContent (not innerHTML) for task data — titles can come from
          // other users sharing the tenant; never render them as HTML.
          const title = document.createElement("div");
          title.textContent = t.title || "(untitled)";
          const status = document.createElement("div");
          status.className = "status";
          status.textContent = t.status || "";
          el.append(title, status);
          list.appendChild(el);
        }
      } catch (e) {
        list.innerHTML = '<p class="empty">Couldn\'t load tasks.</p>';
      }
    })();
  </script>
</body></html>
```

## Authoring checklist

1. Pick a short kebab-case `<id>`; create `<project>/.scarf/miniapps/<id>/`.
2. Write `miniapp.json` with `id` == dir name, `"generated": true`, and the **minimum** permissions.
3. Write a self-contained `index.html` (inline CSS/JS or local files only).
4. Use non-sensitive surfaces first (`context`, `ui`, `store`, `query`/`kanban.read`, `file.read`); request `prompt`/`events` only when needed, and tell the user they'll grant it.
5. Tell the user it's ready in the cockpit's **Mini-apps** panel, and that they'll see a permission preview on first open (sensitive perms start off for generated apps).
