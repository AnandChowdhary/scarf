---
title: Mini-app slide-in uses a trailing overlay, not SwiftUI .inspector (which grows the window)
type: note
permalink: scarf/conventions/mini-app-slide-in-uses-a-trailing-overlay-not-swiftui-inspector-which-grows-the-window
tags:
- swiftui
- window
- mini-app
- gotcha
- macos
---

A mini-app opens in a trailing slide-in OVERLAY (`scarf/scarf/Features/Projects/MiniApp/MiniAppInspectorSurface.swift`, bound in `ContentView` via `.overlay`), NOT SwiftUI `.inspector`.

## Observations
- [gotcha] 🚨 SwiftUI `.inspector` is a real layout COLUMN — adding it raises the content's minimum width, and under `.windowResizability(.contentMinSize)` the WINDOW grows to fit it ("slides wider," sometimes to full screen). #swiftui #window
- [fix] For a slide-in surface that must NOT resize the window, use a trailing `.overlay`: `GeometryReader`, panel pinned to ~74% width (min 420, leave ≥220 for the sidebar + a cockpit sliver), a `Color.clear.allowsHitTesting(false)` left strip so the cockpit stays interactive (non-modal), a leading drag-resize handle, opaque `windowBackgroundColor`. #fix
- [pattern] One mini-app at a time via `AppCoordinator.presentedMiniApp`; the host closes through an injected `onClose` that clears the slot, NOT `@Environment(\.dismiss)` (an overlay isn't a sheet). Each open mini-app spawns its own `hermes acp`, so single-presentation avoids process proliferation.
- [why] Opening a mini-app via `.inspector` grew the whole app window — the bug this pattern replaced.

## Relations
- part_of [[Phase-1 Milestone 2: Mini-apps — implementation decisions]]
- relates_to [[SwiftUI WindowGroup frame persistence needs manual UserDefaults + setFrame]]
