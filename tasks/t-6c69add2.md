---
id: t-6c69add2
title: Add wiki.sh sync subcommand (strip frontmatter, wiki/ → .wiki-worktree/)
status: done
added: 2026-06-28
---

## Description

Durable fix for the v2.15.0 wiki-publish gotcha (see operations/wiki-publish-must-strip-memophant-yaml-frontmatter-wiki). The publish clone .wiki-worktree/ must be frontmatter-free, but the Memophant-managed wiki/*.md source carries YAML frontmatter; a manual `cp` reintroduces the stray-heading artifact on GitHub.

Add a `wiki.sh sync` subcommand: copy top-level wiki/*.md → .wiki-worktree/ (NOT wiki/roadmap/, which is an internal program doc not published to the flat GitHub wiki), stripping ONLY the leading `---`…`---` frontmatter block from each (preserve mid-document `---` horizontal rules). Then the normal flow is `wiki.sh sync && wiki.sh commit "…" && wiki.sh push`. Update the usage/help header. Real-test the strip against a frontmatter file + a file with mid-doc rules; adversarial audit; clean commit. Do NOT push.

## Plan



## Artifacts



