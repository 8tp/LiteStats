import SwiftUI

@main
struct LiteStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { }
    }
}

// ---------------------------------------------------------------------------
// AppDelegate — owns NSStatusItem, NSPopover, and StatsModel.
// Creates / destroys the SwiftUI view hierarchy on popover open / close
// so memory is reclaimed when the panel is dismissed.
// ---------------------------------------------------------------------------

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let stats = StatsModel()

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --- Status item ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                   accessibilityDescription: "LiteStats")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // --- Popover ---
        popover.behavior = .transient
        popover.delegate = self

    }

    // MARK: - Toggle popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }

        // Create a fresh SwiftUI view hierarchy each time the popover opens
        let hostingController = NSHostingController(
            rootView: ContentView().environment(stats)
        )
        popover.contentViewController = hostingController

        stats.panelVisible = true
        stats.fullRefresh()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        stats.panelVisible = false
        stats.topProcesses = []

        // Release the SwiftUI view hierarchy to free memory
        popover.contentViewController = nil
    }

}
