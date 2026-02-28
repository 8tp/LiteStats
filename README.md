# LiteStats

A lightweight, native macOS menu bar app for real-time system monitoring.

## Requirements

- macOS 14.0+ (Sonoma or later)
- Xcode 15.3+
- No external dependencies

## Features

- **CPU usage** — delta-based % using `host_statistics(HOST_CPU_LOAD_INFO)`
- **RAM** — active + wired + compressor pages via `host_statistics64(HOST_VM_INFO64)`
- **Storage** — boot volume free/total via `URL.resourceValues`
- **Battery** — level, charging state, health %, cycle count via IOKit / IOPowerSources
- **Device Health** — automatic summary with warnings for low battery health, high CPU/RAM, low disk
- **Preferences** — adjustable polling interval (1–10 s)
- Hidden from Dock (`LSUIElement = YES`)

## Build & Run

1. Open `LiteStats.xcodeproj` in Xcode
2. Select the **LiteStats** scheme
3. Set **Signing & Capabilities** → Team to your Apple ID (free team is fine for local use)
4. Press `⌘R` to build and run

> **Note:** The app is sandboxed with `com.apple.security.app-sandbox = false` so IOKit battery
> access works without entitlements. For App Store distribution you would need to add the
> appropriate entitlements or use a helper process.

## Project Structure

```
LiteStats/
├── LiteStatsApp.swift       — @main entry, MenuBarExtra scene
├── StatsModel.swift         — @Observable polling engine (CPU/RAM/Storage/Battery)
├── ContentView.swift        — Popover UI (StatRow cards, ProgressBar)
├── PreferencesView.swift    — Settings sheet (interval slider, device info)
├── Info.plist               — LSUIElement=YES, deployment target
└── Assets.xcassets/         — AccentColor, AppIcon stubs
```

## Architecture Notes

- `StatsModel` is `@Observable` (Swift 5.9 Observation framework) and lives on the main actor via the `@State` in `LiteStatsApp`.
- CPU % is computed as a **delta** between successive `host_cpu_load_info` snapshots to avoid the "first-read = 100%" spike.
- The timer uses `Timer.scheduledTimer` added to `.common` run-loop mode so it fires even during UI tracking.
- Battery health reads `MaxCapacity` / `DesignCapacity` from `AppleSmartBattery` IORegistry entry.
