import SwiftUI

// ---------------------------------------------------------------------------
// PreferencesView — inline preferences panel (no sheet, avoids panel dismiss).
// ---------------------------------------------------------------------------

struct PreferencesView: View {
    @Environment(StatsModel.self) private var stats
    /// Called by Cancel and Save buttons to navigate back to the stats panel
    let onDismiss: () -> Void

    // Local copies so changes are only applied on "Save"
    @State private var interval: Double = 3
    @State private var textSize: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(Color.accentColor)
                Text("LiteStats Preferences")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Update Interval")
                            Spacer()
                            Text(intervalLabel(interval))
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Slider(value: $interval, in: 1...10, step: 1)
                            .tint(.accentColor)
                        HStack {
                            Text("1 s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("10 s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Polling")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text Size")
                            Spacer()
                            Text(textSizeLabel(textSize))
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Slider(value: $textSize, in: 0...4, step: 1)
                            .tint(.accentColor)
                        HStack {
                            Text("Default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Maximum")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    LabeledContent("CPU Cores", value: "\(stats.cpuCores)")
                    LabeledContent("Physical RAM", value: formatBytes(stats.ramTotal))
                    if stats.hasBattery, let cycles = stats.batteryCycles {
                        LabeledContent("Battery Cycles", value: "\(cycles)")
                    }
                    if stats.hasBattery, let health = stats.batteryHealth {
                        LabeledContent("Battery Health", value: "\(health)%")
                    }
                } header: {
                    Text("Device Info")
                }
            }
            .formStyle(.grouped)

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    stats.updateInterval = interval
                    stats.textSizeOffset = CGFloat(textSize)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 320)
        .onAppear {
            interval = stats.updateInterval
            textSize = Double(stats.textSizeOffset)
        }
    }

    // MARK: - Helpers

    private func intervalLabel(_ s: Double) -> String {
        s == 1 ? "Every second" : "Every \(Int(s)) seconds"
    }

    private func textSizeLabel(_ size: Double) -> String {
        switch Int(size) {
        case 0: return "Default"
        case 1: return "Medium"
        case 2: return "Large"
        case 3: return "Extra Large"
        case 4: return "Maximum"
        default: return "Default"
        }
    }

    private func formatBytes(_ bytes: some BinaryInteger) -> String {
        let gb = Double(Int64(bytes)) / 1_073_741_824
        return String(format: "%.0f GB", gb)
    }
}
