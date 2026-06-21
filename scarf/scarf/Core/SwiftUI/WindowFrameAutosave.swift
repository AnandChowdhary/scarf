import AppKit
import SwiftUI

/// Persist a SwiftUI `WindowGroup` window's frame (size + position) across
/// app launches by hooking into AppKit's `NSWindow.setFrameAutosaveName`.
///
/// **Why this exists.** SwiftUI's `WindowGroup` exposes `.defaultSize`,
/// `.windowResizability`, and (on macOS Sonoma+) various scene modifiers
/// — but not a "remember this window's size between launches" affordance.
/// Apple's documented escape hatch is AppKit's `setFrameAutosaveName(_:)`,
/// which writes the window's frame to UserDefaults on resize/move and
/// reads it back on next `makeKey`. We bridge into it from SwiftUI via an
/// invisible `NSViewRepresentable` that finds the hosting `NSWindow`
/// and stamps the autosave name once it appears.
///
/// **Usage.**
///     ContentView()
///         .windowFrameAutosave("Scarf.\(context.id)")
///
/// Pass a stable identifier per logical window. Different identifiers per
/// window are required by AppKit ("no two windows can be associated with
/// the same name simultaneously" — `NSWindow.setFrameAutosaveName(_:)`
/// docs). For Scarf's multi-window-per-server model, keying off
/// `ServerID` gives each server window its own remembered frame.
///
/// **First-launch behaviour.** No saved frame exists → AppKit leaves the
/// window at whatever frame SwiftUI's `.defaultSize` produced. After the
/// first user resize, AppKit autosaves and subsequent opens restore the
/// new frame.
///
/// **What it doesn't do.** Doesn't capture/restore fullscreen state
/// (AppKit handles that separately and reasonably). Doesn't try to
/// override window state restoration when the user has the system-level
/// "Close windows when quitting an application" setting OFF — that
/// pathway runs first and we just ride alongside.
struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The hosting NSWindow isn't attached to this view yet at
        // makeNSView time — SwiftUI mounts the AppKit view hierarchy
        // before the window assignment propagates. Defer one runloop
        // iteration so `view.window` is non-nil when we bind.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            Self.bind(window, to: name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI may swap the host window in rare cases (window
        // restoration after a relaunch, scene reuse). Re-bind on update
        // so we don't lose the autosave binding silently. `bind` is
        // idempotent (it no-ops once the window already carries `name`),
        // so this never re-restores over a mid-session user resize.
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            Self.bind(window, to: name)
        }
    }

    /// Restore the saved frame for `name`, then enable autosave so future
    /// resizes/moves persist.
    ///
    /// **Why `setFrameUsingName` is the load-bearing call.**
    /// `setFrameAutosaveName` only *saves* the frame on change — it does
    /// NOT reliably re-apply a previously-saved frame once SwiftUI's
    /// `.defaultSize` has already positioned and shown the window (which
    /// happens before this deferred bind runs). `setFrameUsingName`
    /// explicitly reads the saved frame out of `UserDefaults` and applies
    /// it, overriding `.defaultSize`. Without it the window saved its size
    /// but always reopened at the default — the long-standing "window
    /// doesn't remember its size" bug.
    ///
    /// Order matters: restore FIRST, then set the autosave name. Setting
    /// the name first would persist the just-shown `.defaultSize` frame
    /// over the saved one before we get a chance to restore it.
    ///
    /// Guarded on `frameAutosaveName == name` so it binds exactly once per
    /// window: re-running on every `updateNSView` would yank the window
    /// back to the saved frame mid-resize.
    private static func bind(_ window: NSWindow, to name: String) {
        guard window.frameAutosaveName != name else { return }
        window.setFrameUsingName(name)      // restore saved frame (overrides .defaultSize); no-op on first launch
        window.setFrameAutosaveName(name)   // enable ongoing persistence
    }
}

extension View {
    /// Persist this view's hosting window's frame (size + position)
    /// across launches under `name`. See `WindowFrameAutosave` for
    /// details.
    func windowFrameAutosave(_ name: String) -> some View {
        background(WindowFrameAutosave(name: name))
    }
}
