import AppKit
import SwiftUI

/// Persist a SwiftUI `WindowGroup` window's frame (size + position) across
/// launches with **manual** UserDefaults persistence + `setFrame` —
/// deliberately NOT AppKit's `setFrameAutosaveName`.
///
/// **Why manual (the previous fix didn't work).** `WindowGroup` assigns the
/// window its OWN derived `frameAutosaveName`
/// (`SwiftUI.PresentedWindowContent<…>-AppWindow-1`) and keeps re-asserting
/// it, so a custom `setFrameAutosaveName(_:)` never sticks — and SwiftUI's
/// own autosave SAVES the frame but never re-applies it on close/reopen (the
/// window comes back at `.defaultSize`). Verified against the app's
/// `UserDefaults`: only the SwiftUI-derived `NSWindow Frame …AppWindow-1`
/// key is ever written, never ours. So instead of fighting the autosave
/// name, we own the whole loop: read our own key and `setFrame` once the
/// window appears (overriding `.defaultSize`), and write the frame back on
/// every user resize/move.
///
/// **Usage.** `ContentView().windowFrameAutosave("Scarf.Window.\(context.id)")`
/// — pass a stable per-window key (keying off `ServerID` gives each server
/// window its own remembered frame).
///
/// **First launch.** No saved frame → restore is a no-op → the window uses
/// SwiftUI's `.defaultSize`. After the first resize it's remembered.
///
/// **What it doesn't do.** Doesn't capture/restore fullscreen state (AppKit
/// handles that). With one window per server (Scarf's norm) the per-key
/// model is exact; two simultaneous windows of the same server would share
/// a key (last-writer-wins), which is acceptable.
struct WindowFrameAutosave: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> NSView {
        let view = FrameTrackerView()
        view.persistenceKey = "ScarfWindowFrame.\(key)"
        // The hosting NSWindow isn't attached at makeNSView time — defer a
        // runloop so `view.window` is non-nil (and SwiftUI has finished its
        // initial sizing, which the restore below then overrides).
        DispatchQueue.main.async { [weak view] in view?.attachToWindow() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Fallback if the window wasn't attached yet on the makeNSView pass.
        // `attachToWindow` is guarded to run its restore + observer install
        // exactly once, so this never re-restores over a mid-session resize.
        DispatchQueue.main.async { [weak nsView] in
            (nsView as? FrameTrackerView)?.attachToWindow()
        }
    }
}

/// Invisible view that restores its window's saved frame once, then writes
/// the frame back on every user resize/move.
private final class FrameTrackerView: NSView {
    var persistenceKey = ""
    private var attached = false
    private var observers: [NSObjectProtocol] = []

    func attachToWindow() {
        guard !attached, let window = self.window, !persistenceKey.isEmpty else { return }
        attached = true

        // 1. Restore the saved frame, overriding SwiftUI's `.defaultSize`.
        if let saved = UserDefaults.standard.string(forKey: persistenceKey) {
            let rect = NSRectFromString(saved)
            if rect.width >= 200, rect.height >= 150 {   // ignore a garbage/zero rect
                window.setFrame(rect, display: true)
            }
        }

        // 2. Save on every user resize/move. Capture the key by value and
        //    the window weakly so these stored closures form no retain cycle
        //    with this view (which owns `observers`). Whatever the frame is
        //    becomes what we restore next launch — saving the initial frame
        //    is harmless; a later resize overwrites it.
        let key = persistenceKey
        let save: (Notification) -> Void = { [weak window] _ in
            guard let window else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main, using: save))
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save))
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension View {
    /// Persist this view's hosting window's frame (size + position) across
    /// launches under `key`. See `WindowFrameAutosave`.
    func windowFrameAutosave(_ key: String) -> some View {
        background(WindowFrameAutosave(key: key))
    }
}
