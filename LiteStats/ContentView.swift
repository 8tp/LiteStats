import SwiftUI

// ---------------------------------------------------------------------------
// ContentView — the panel that drops down from the menu-bar icon.
// Layout: Header → Uptime/Thermals → CPU/Memory/Storage → Battery →
//         Action buttons (RAM Usage, Trends, Network) → Footer
// ---------------------------------------------------------------------------

struct ContentView: View {
    @Environment(StatsModel.self) private var stats

    // Expandable sections
    @State private var showRAMUsage = false
    @State private var showTrends = false
    @State private var showNetwork = false

    /// Shorthand for the user's text-size offset preference
    private var ts: CGFloat { stats.textSizeOffset }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 6) {
                uptimeThermalCard
                cpuCard
                memoryCard
                storageCard

                if stats.hasBattery {
                    batteryCard
                }

                actionButtons

                if showRAMUsage {
                    ramUsagePanel
                }
                if showTrends {
                    trendsPanel
                }
                if showNetwork {
                    networkPanel
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            footer
        }
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stats.healthSummary == "All systems nominal" ? .green : .orange)
                .frame(width: 7, height: 7)
            Text("LiteStats")
                .font(.system(size: 14 + ts, weight: .semibold))
            Spacer()
            Text("\(Int(stats.updateInterval))s")
                .font(.system(size: 11 + ts, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Uptime & Thermals

    private var uptimeThermalCard: some View {
        let thermalColor: Color = switch stats.thermalSeverity {
            case 0: .green
            case 1: .yellow
            case 2: .orange
            case 3: .red
            default: .secondary
        }

        return HStack {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 12 + ts))
                    .foregroundStyle(.secondary)
                Text(stats.uptimeString)
                    .font(.system(size: 12 + ts, weight: .medium, design: .monospaced))
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 12 + ts))
                    .foregroundStyle(thermalColor)
                if let temp = stats.cpuTemperature {
                    Text(String(format: "%.0f°C", temp))
                        .font(.system(size: 12 + ts, weight: .medium, design: .monospaced))
                        .foregroundStyle(thermalColor)
                } else {
                    Text(stats.thermalState)
                        .font(.system(size: 12 + ts, weight: .medium))
                        .foregroundStyle(thermalColor)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - CPU Card

    private var cpuCard: some View {
        StatRow(
            icon: "cpu",
            iconColor: .blue,
            label: "CPU",
            subtitle: "\(stats.cpuCores) cores · \(String(format: "%.1f%%", stats.cpuPercent))"
        ) {
            ProgressBar(value: stats.cpuPercent / 100, tint: .blue)
        }
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        StatRow(
            icon: "memorychip",
            iconColor: .indigo,
            label: "Memory",
            subtitle: "\(formatBytes(stats.ramUsed)) / \(formatBytes(stats.ramTotal)) (\(Int(stats.ramPercent))%)"
        ) {
            ProgressBar(value: stats.ramPercent / 100, tint: .indigo)
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        let used = stats.storageTotal - stats.storageFree
        let pct  = stats.storageTotal > 0 ? Double(used) / Double(stats.storageTotal) : 0
        let color: Color = pct > 0.9 ? .red : pct > 0.75 ? .orange : .cyan

        return StatRow(
            icon: "internaldrive",
            iconColor: color,
            label: "Storage",
            subtitle: "\(formatBytes(stats.storageFree)) free / \(formatBytes(stats.storageTotal))"
        ) {
            ProgressBar(value: pct, tint: color)
        }
    }

    // MARK: - Battery Card (numbers only, no bars)

    private var batteryCard: some View {
        let level = stats.batteryLevel ?? 0

        return VStack(spacing: 6) {
            // Top row: Charge + Health
            HStack(spacing: 6) {
                batteryMiniStat(
                    icon: batteryIcon(level: level, charging: stats.batteryCharging),
                    iconColor: level < 20 ? .red : level < 40 ? .orange : .green,
                    label: "Charge",
                    value: "\(level)%\(stats.batteryCharging ? " ⚡" : "")"
                )
                batteryMiniStat(
                    icon: "heart.fill",
                    iconColor: healthColor(stats.batteryHealth),
                    label: "Health",
                    value: stats.batteryHealth.map { "\($0)%" } ?? "—"
                )
            }
            // Bottom row: Cycles + Condition
            HStack(spacing: 6) {
                batteryMiniStat(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .secondary,
                    label: "Cycles",
                    value: stats.batteryCycles.map { "\($0)" } ?? "—"
                )
                batteryMiniStat(
                    icon: conditionIcon(stats.batteryCondition),
                    iconColor: conditionColor(stats.batteryCondition),
                    label: "Condition",
                    value: stats.batteryCondition
                )
            }
        }
    }

    private func batteryMiniStat(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12 + ts))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11 + ts))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12 + ts, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 4) {
            ToggleButton(
                label: "Processes",
                icon: "memorychip.fill",
                isActive: showRAMUsage
            ) {
                showRAMUsage.toggle()
                stats.showProcesses = showRAMUsage
                if showRAMUsage {
                    stats.fullRefresh()
                } else {
                    stats.topProcesses = []
                }
            }

            ToggleButton(
                label: "Trends",
                icon: "chart.xyaxis.line",
                isActive: showTrends
            ) { showTrends.toggle() }

            ToggleButton(
                label: "Network",
                icon: "network",
                isActive: showNetwork
            ) { showNetwork.toggle() }
        }
    }

    // MARK: - RAM Usage Panel (scrollable process list)

    private var ramUsagePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "memorychip.fill")
                    .foregroundStyle(.indigo)
                    .font(.system(size: 13 + ts, weight: .semibold))
                Text("Memory Consumers")
                    .font(.system(size: 13 + ts, weight: .semibold))
                Spacer()
                Text("\(stats.topProcesses.count) processes")
                    .font(.system(size: 11 + ts))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            if stats.topProcesses.isEmpty {
                Text("No data yet")
                    .font(.system(size: 12 + ts))
                    .foregroundStyle(.secondary)
            } else {
                let rowHeight: CGFloat = 28
                let listHeight = min(CGFloat(stats.topProcesses.count) * rowHeight, 300)
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(stats.topProcesses) { proc in
                            ProcessRow(process: proc, maxMB: stats.topProcesses.first?.memoryMB ?? 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.visible)
                .frame(height: listHeight)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Trends Panel

    private var trendsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13 + ts, weight: .semibold))
                Text("Performance Trends")
                    .font(.system(size: 13 + ts, weight: .semibold))
                Spacer()
                Text("\(stats.cpuTrend.count) samples")
                    .font(.system(size: 11 + ts))
                    .foregroundStyle(.secondary)
            }

            // CPU sparkline
            VStack(alignment: .leading, spacing: 2) {
                Text("CPU")
                    .font(.system(size: 11 + ts, weight: .medium))
                    .foregroundStyle(.secondary)
                Sparkline(data: stats.cpuTrend.map(\.value), color: .blue, height: 30)
            }

            // RAM sparkline
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory")
                    .font(.system(size: 11 + ts, weight: .medium))
                    .foregroundStyle(.secondary)
                Sparkline(data: stats.ramTrend.map(\.value), color: .indigo, height: 30)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Network Panel

    private var networkPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.teal)
                    .font(.system(size: 13 + ts, weight: .semibold))
                Text("Network")
                    .font(.system(size: 13 + ts, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // IP address
            HStack {
                Text("Local IP")
                    .font(.system(size: 12 + ts, weight: .medium))
                Spacer()
                Text(stats.localIP)
                    .font(.system(size: 12 + ts, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Divider().padding(.horizontal, 8)

            // Download
            HStack {
                Label {
                    Text("Download")
                        .font(.system(size: 12 + ts, weight: .medium))
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12 + ts))
                }
                Spacer()
                Text(formatSpeed(stats.netBytesRecvPerSec))
                    .font(.system(size: 12 + ts, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Divider().padding(.horizontal, 8)

            // Upload
            HStack {
                Label {
                    Text("Upload")
                        .font(.system(size: 12 + ts, weight: .medium))
                } icon: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 12 + ts))
                }
                Spacer()
                Text(formatSpeed(stats.netBytesSentPerSec))
                    .font(.system(size: 12 + ts, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button { stats.fullRefresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13 + ts))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")

            Button { PreferencesWindowController.open(stats: stats) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13 + ts))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Preferences")

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 12 + ts))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.7))
            .help("Quit LiteStats")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: some BinaryInteger) -> String {
        let b = Int64(bytes)
        let gb = Double(b) / 1_073_741_824
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1024) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(b) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    private func formatSpeed(_ bytesPerSec: UInt64) -> String {
        let kb = Double(bytesPerSec) / 1024
        if kb < 1 { return "0 KB/s" }
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB/s", mb)
    }

    private func batteryIcon(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 11...: return "battery.25percent"
        default:    return "battery.0percent"
        }
    }

    private func healthColor(_ health: Int?) -> Color {
        guard let h = health else { return .secondary }
        if h < 80 { return .red }
        if h < 90 { return .orange }
        return .green
    }

    private func conditionIcon(_ condition: String) -> String {
        switch condition.lowercased() {
        case "normal": return "checkmark.circle.fill"
        case let s where s.contains("service"): return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private func conditionColor(_ condition: String) -> Color {
        switch condition.lowercased() {
        case "normal": return .green
        case let s where s.contains("service"): return .red
        default: return .orange
        }
    }
}

// ---------------------------------------------------------------------------
// StatRow — reusable labelled card with a progress bar
// ---------------------------------------------------------------------------

private struct StatRow<Content: View>: View {
    @Environment(StatsModel.self) private var stats
    let icon: String
    let iconColor: Color
    let label: String
    let subtitle: String
    @ViewBuilder let content: Content

    private var ts: CGFloat { stats.textSizeOffset }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 13 + ts, weight: .semibold))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13 + ts, weight: .semibold))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 12 + ts, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// ---------------------------------------------------------------------------
// ProgressBar — thin, tinted progress track
// ---------------------------------------------------------------------------

private struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint)
                    .frame(width: geo.size.width * value.clamped(to: 0...1), height: 6)
            }
        }
        .frame(height: 6)
    }
}

// ---------------------------------------------------------------------------
// ToggleButton — compact toggle for expandable sections
// ---------------------------------------------------------------------------

private struct ToggleButton: View {
    @Environment(StatsModel.self) private var stats
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    private var ts: CGFloat { stats.textSizeOffset }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12 + ts))
                Text(label)
                    .font(.system(size: 12 + ts, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
    }
}

// ---------------------------------------------------------------------------
// ProcessRow — single process entry with mini bar + hover popover
// ---------------------------------------------------------------------------

private struct ProcessRow: View {
    @Environment(StatsModel.self) private var stats
    let process: ProcessMemInfo
    let maxMB: Double
    @State private var isHovered = false
    @State private var cachedIcon: NSImage?
    @State private var cachedActivatable: Bool = false

    private var ts: CGFloat { stats.textSizeOffset }

    private var runningApp: NSRunningApplication? {
        NSRunningApplication(processIdentifier: process.id)
    }

    private var displayIcon: NSImage {
        cachedIcon ?? NSWorkspace.shared.icon(for: .unixExecutable)
    }

    var body: some View {
        let content = HStack(spacing: 6) {
            Image(nsImage: displayIcon)
                .resizable()
                .frame(width: 16, height: 16)

            Text(process.name)
                .font(.system(size: 11 + ts))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 95, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.indigo)
                        .frame(width: geo.size.width * (process.memoryMB / maxMB).clamped(to: 0...1), height: 4)
                }
            }
            .frame(height: 4)

            Text(String(format: "%.0f MB", process.memoryMB))
                .font(.system(size: 11 + ts, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contextMenu {
            if processURL() != nil {
                Button { showInFinder() } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            if cachedActivatable {
                Button { activateProcess(pid: process.id) } label: {
                    Label("Bring to Front", systemImage: "macwindow")
                }
            }
            Divider()
            Button { quitProcess() } label: {
                Label("Quit Process", systemImage: "xmark.circle")
            }
            Button(role: .destructive) { forceQuitProcess() } label: {
                Label("Force Quit", systemImage: "xmark.circle.fill")
            }
        }

        if cachedActivatable {
            Button {
                activateProcess(pid: process.id)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .onHover { hovering in isHovered = hovering }
            .help("Click to bring \(process.name) to front · Right-click for options")
            .onAppear { cacheAppInfo() }
        } else {
            content
                .onHover { hovering in isHovered = hovering }
                .help("Right-click for options")
                .onAppear { cacheAppInfo() }
        }
    }

    private func cacheAppInfo() {
        let app = runningApp
        cachedIcon = app?.icon
        cachedActivatable = app?.activationPolicy == .regular
    }

    // MARK: - Actions

    private func processURL() -> URL? {
        if let bundleURL = runningApp?.bundleURL {
            return bundleURL
        }
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(process.id, &pathBuffer, UInt32(pathBuffer.count))
        guard ret > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: pathBuffer))
    }

    private func showInFinder() {
        guard let url = processURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func activateProcess(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }

    private func quitProcess() {
        if let app = runningApp {
            app.terminate()
        } else {
            kill(process.id, SIGTERM)
        }
    }

    private func forceQuitProcess() {
        if let app = runningApp {
            app.forceTerminate()
        } else {
            kill(process.id, SIGKILL)
        }
    }
}

// ---------------------------------------------------------------------------
// Sparkline — mini chart for CPU/RAM trend data
// ---------------------------------------------------------------------------

private struct Sparkline: View {
    let data: [Double]
    let color: Color
    let height: CGFloat

    var body: some View {
        if data.count < 2 {
            Text("Collecting data…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(height: height)
        } else {
            GeometryReader { geo in
                let maxVal = max(data.max() ?? 100, 1)
                let stepX = geo.size.width / CGFloat(data.count - 1)

                Path { path in
                    for (i, val) in data.enumerated() {
                        let x = stepX * CGFloat(i)
                        let y = geo.size.height * (1 - CGFloat(val / maxVal))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Filled area under the line
                Path { path in
                    for (i, val) in data.enumerated() {
                        let x = stepX * CGFloat(i)
                        let y = geo.size.height * (1 - CGFloat(val / maxVal))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: geo.size.height))
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: stepX * CGFloat(data.count - 1), y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.12))
            }
            .frame(height: height)
        }
    }
}
