import AppKit
import SwiftUI

// ---------------------------------------------------------------------------
// PreferencesWindowController — opens the Preferences view in a standalone
// NSWindow so it never steals focus from the MenuBarExtra panel.
// ---------------------------------------------------------------------------

final class PreferencesWindowController: NSWindowController {

    private static var shared: PreferencesWindowController?

    /// Open (or bring-to-front) the preferences window, passing in the shared StatsModel.
    static func open(stats: StatsModel) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LiteStats Preferences"
        window.isReleasedWhenClosed = false
        window.center()

        let rootView = PreferencesView(onDismiss: {
            shared?.window?.close()
            shared = nil
        })
        .environment(stats)

        window.contentView = NSHostingView(rootView: rootView)

        let controller = PreferencesWindowController(window: window)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
