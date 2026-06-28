---
title: Wiki publish must strip Memophant YAML frontmatter (.wiki-worktree)
type: note
permalink: scarf/operations/wiki-publish-must-strip-memophant-yaml-frontmatter-wiki
created: 2026-06-28
updated: 2026-06-28
source_sha: ec37fcedb753d81a12b451740404b978df1873d6
source_paths: scripts/wiki.sh
tags:
- wiki
- release
- gotcha
- memophant
---

# Wiki publish must strip Memophant YAML frontmatter

## Observations

- [gotcha] The repo keeps TWO copies of every wiki page: `wiki/*.md` (Memophant-managed source — carries YAML frontmatter `---\ntitle: …\ntype: note\npermalink: scarf-wiki/…\n---`) and `.wiki-worktree/*.md` (the clone of `github.com:awizemann/scarf.wiki.git` that actually publishes). The published GitHub wiki pages are frontmatter-FREE (they start with the `#` H1). #wiki
- [gotcha] GitHub wikis do NOT parse YAML frontmatter. A page that starts with `---\ntitle: Home\n…\n---` renders the frontmatter as a literal **setext H2 heading** ("title: Home type: note permalink: scarf-wiki/home") at the top of the page (and in `_Sidebar`). Seen live 2026-06-28 after the v2.15.0 wiki push. #wiki #bug
- [root-cause] A naive `cp wiki/Foo.md .wiki-worktree/Foo.md` copies the frontmatter into the publish clone → the stray-heading artifact. The publish step MUST strip the leading `---`…`---` block first. `scripts/wiki.sh` has NO `sync` command — it only commit/push/pull/new/touch the `.wiki-worktree/` clone — so the sync is manual and it is on the operator to strip frontmatter. #wiki #rule
- [fix] Strip only the FIRST frontmatter block; leave mid-document `---` horizontal rules (e.g. the `---` before the `_Last updated:` footer) intact. Working awk: `awk 'NR==1 && $0=="---"{infm=1;next} infm{if($0=="---"){infm=0;closed=1};next} closed&&!body&&$0~/^[[:space:]]*$/{next} {body=1;print}' in.md`. Then `./scripts/wiki.sh commit "…"` + `push`. #wiki
- [verify] After push, confirm with `curl -s https://raw.githubusercontent.com/wiki/awizemann/scarf/<Page>.md | head -3` — it should start with the `#` heading, not `---`. #wiki
- [improvement] Candidate durable fix: add a `wiki.sh sync` subcommand that copies `wiki/*.md` → `.wiki-worktree/` (top-level only; skip `wiki/roadmap/`, which is an internal program doc not published) while stripping leading frontmatter, so the next release-prep can't reintroduce this by hand. Not yet implemented. #wiki #followup

## Relations
- relates_to [[Build and Release Workflow]]
- part_of [[Wiki Maintenance Workflow]]
