<h1 align="center">LiteStats</h1>

<p align="center">
  A lightweight, native macOS menu bar app for real-time system monitoring.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/github/license/huntershome/LiteStats" alt="MIT License">
  <img src="https://img.shields.io/badge/dependencies-zero-brightgreen" alt="Zero Dependencies">
</p>

---

LiteStats lives in your menu bar and gives you an instant overview of your Mac's health — CPU, memory, disk, battery, network, thermals, and more — with zero external dependencies and minimal resource usage.

<!-- Screenshot placeholder — replace with an actual screenshot of the popover -->
<!-- ![LiteStats screenshot](docs/screenshot.png) -->

## Features

### System Metrics
- **CPU** — real-time usage percentage with core count
- **Memory** — used vs. total RAM (matches Activity Monitor's calculation)
- **Storage** — free and total space on the boot volume
- **Network** — live upload/download speeds and local IP address

### Battery (laptops)
- Charge level and charging status
- Battery health percentage and condition
- Cycle count

### Diagnostics
- **CPU Temperature** — live reading via SMC (Apple Silicon and Intel)
- **Thermal Pressure** — system thermal state (Nominal / Fair / Serious / Critical)
- **System Uptime** — time since last boot
- **Device Health Summary** — automatic warnings for high CPU/RAM, low disk, degraded battery, or thermal throttling

### Tools
- **Process List** — top memory consumers with app icons, sorted by RAM usage. Right-click to show in Finder, bring to front, quit, or force-quit.
- **Performance Trends** — sparkline charts tracking CPU and memory usage over the last 60 samples

### Preferences
- Adjustable polling interval (1–10 seconds)
- Adjustable text size (5 levels)
- Device info at a glance

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.3+ (to build from source)

## Installation

### Build from source

```sh
git clone https://github.com/huntershome/LiteStats.git
cd LiteStats
open LiteStats.xcodeproj
```

1. Set **Signing & Capabilities → Team** to your Apple ID (free personal team works)
2. Press **⌘R** to build and run

Or build from the command line:

```sh
xcodebuild -project LiteStats.xcodeproj -scheme LiteStats -configuration Debug build
```

> **Note:** Sandboxing is disabled so IOKit battery and SMC access works without entitlements. For App Store distribution, you would need to add appropriate entitlements or use a helper process.

## Architecture

```
LiteStats/
├── LiteStatsApp.swift                — @main entry point, MenuBarExtra scene
├── StatsModel.swift                  — @Observable polling engine (all metrics)
├── ContentView.swift                 — Menu bar panel UI and components
├── PreferencesView.swift             — Settings panel (interval, text size, device info)
├── PreferencesWindowController.swift — NSWindow wrapper for preferences
└── Assets.xcassets/                  — App icon and accent color
```

- **StatsModel** is `@Observable` (Swift 5.9 Observation framework) and uses a timer on the `.common` run-loop mode so updates continue during UI interaction.
- CPU usage is computed as a delta between successive snapshots to avoid first-read spikes.
- The app hides from the Dock and App Switcher (`LSUIElement = YES`).
- No external dependencies — everything is built on Foundation, SwiftUI, and IOKit.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) — see the LICENSE file for details.
