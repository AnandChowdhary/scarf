---
title: Path containment for untrusted dirs must resolve symlinks, not just normalize lexically
type: note
permalink: scarf/conventions/path-containment-for-untrusted-dirs-must-resolve-symlinks-not-just-normalize-lexically
tags:
- security
- miniapps
- webkit
- convention
- gotcha
created: 2026-06-16
updated: 2026-06-16
---

When serving files out of a directory that untrusted or agent-writable content can populate (the mini-app `scarf-miniapp://` host is the live case), a lexical path-containment check is NOT enough — it's a real escape vector.

## Observations
- [gotcha] `NSString.standardizingPath` (and any purely-lexical normalize) resolves `..`/`.`/`~` but does NOT resolve symlinks. A symlink planted inside the served dir (`app/leak -> ~/.hermes/auth.json`) passes a `hasPrefix(base + "/")` check, then `FileManager.contents(atPath:)` reads THROUGH it — leaking secrets into the page DOM. Found in the M2 fresh-eyes review (HIGH); the mini-app dir is agent-writable + template-delivered, so it's plantable. #security
- [fix] Containment for an untrusted dir must (1) lexically reject `..` etc., THEN (2) run BOTH the base and the candidate through `URL(fileURLWithPath:).resolvingSymlinksInPath()` and re-check `hasPrefix`. Resolve BOTH sides, not just the file — otherwise legit serves break when the base itself is under a symlinked prefix (macOS `/tmp` → `/private/tmp`, and test temp dirs under `/var` → `/private/var`). Implemented as `MiniAppAssetResolver.containedFilePath` (ScarfCore); the WebKit scheme handler reads only through it. #fix
- [pattern] Keep the lexical check pure/unit-testable (`resolvedPath`) and add the FS-touching symlink+existence layer as a separate function (`containedFilePath`) so the escape case is unit-testable with a real planted symlink — don't bury it in the WebKit handler where it can't be tested. #testing
- [related] Same review fixed two more: narrowing a mini-app's granted permissions didn't affect a running `WKWebView` (dispatcher captured at mount) — fix is `.id(grantedSet)` on the host so a tighter grant rebuilds it; and `minBridgeVersion` is now enforced at mount (`MiniAppBridge.satisfiesMinBridgeVersion`) instead of being a doc claim with no code. #miniapps

## Relations
- relates_to [[Phase-1 Milestone 1: First-Class Project Object — implementation decisions]]
