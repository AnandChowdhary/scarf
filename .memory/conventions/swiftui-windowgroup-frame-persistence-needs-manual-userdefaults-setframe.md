---
title: SwiftUI WindowGroup frame persistence needs manual UserDefaults + setFrame
type: note
permalink: scarf/conventions/swiftui-windowgroup-frame-persistence-needs-manual-userdefaults-setframe
tags:
- swiftui
- window
- macos
- gotcha
- persistence
---

macOS Scarf persists each window's frame (size + position) across launches MANUALLY — its own UserDefaults key + `setFrame` on appear — deliberately NOT AppKit's `setFrameAutosaveName`/`setFrameUsingName`, and NOT relying on SwiftUI's built-in autosave. See `scarf/scarf/Core/SwiftUI/WindowFrameAutosave.swift` (applied at the `WindowGroup` content via `.windowFrameAutosave("Scarf.Window.<serverID>")`).

## Observations
- [gotcha] 🚨 A SwiftUI `WindowGroup` assigns its window an OWN derived `frameAutosaveName` (`SwiftUI.PresentedWindowContent<…>-AppWindow-1`) and keeps re-asserting it, so a custom `setFrameAutosaveName(_:)` / `setFrameUsingName(_:)` never sticks. #swiftui #window
- [evidence] Verified against the app's `UserDefaults`: only the SwiftUI-derived `NSWindow Frame …AppWindow-1` key is ever written — never a custom autosave key.
- [gotcha] SwiftUI's own autosave SAVES the frame but never RE-APPLIES it on close/reopen — the window returns to `.defaultSize`. "It saves" is not "it restores".
- [fix] Own the whole loop: an invisible `NSViewRepresentable` reads our own `ScarfWindowFrame.<key>` UserDefaults key and `setFrame`s once the window appears (overriding `.defaultSize`), then writes back on `didEndLiveResize` / `didMove`. Key is per-`ServerID` so each server window remembers its own geometry. #fix
- [pattern] Restore must run EXACTLY once (guard a `attached` flag) or it stomps a mid-session user resize; capture the window weakly in the save closures; remove observers in `deinit` (audit-confirmed: no retain cycle, observers released).
- [why] Fixes the long-standing "window doesn't remember its size across close/reopen" bug.

## Relations
- relates_to [[Cache feature VMs in AppCoordinator to stop re-fetch on sidebar section switches]]
