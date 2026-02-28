import SwiftUI

@main
struct LiteStatsApp: App {
    @State private var stats = StatsModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(stats)
        } label: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
        .menuBarExtraStyle(.window)
    }
}
