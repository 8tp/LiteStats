# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LiteStats** is a native macOS menu bar application for real-time system monitoring. It is written entirely in Swift with zero external dependencies and requires macOS 14.0+ (Sonoma) and Xcode 15.3+.

## Build & Run

This is a pure Xcode project — there are no package managers, build scripts, or Makefiles.

**From Xcode:**
1. Open `LiteStats.xcodeproj`
2. Select the **LiteStats** scheme
3. Set Signing & Capabilities → Team to your Apple ID
4. Press `⌘R`

**From the command line:**
```sh
xcodebuild -project LiteStats/LiteStats.xcodeproj -scheme LiteStats -configuration Debug build
```

There are no unit tests in this project.

## Architecture

The app uses a clean three-layer separation:

| File | Role |
|------|------|
| `LiteStatsApp.swift` | `@main` entry point; creates `MenuBarExtra` scene; passes `StatsModel` to views |
| `StatsModel.swift` | `@Observable` polling engine; all system metric collection logic |
| `ContentView.swift` | Menu bar popover UI (320pt fixed width); `StatRow` and `ProgressBar` components |
| `PreferencesView.swift` | Settings sheet (interval slider, device info display) |
| `PreferencesWindowController.swift` | Singleton `NSWindow` wrapper for preferences; prevents duplicate windows |

### StatsModel (core engine)

- `@Observable` class (Swift 5.9 Observation framework), lives on the main actor via `@State` in the app entry point.
- Timer is added to `.common` RunLoop mode so it fires during UI tracking loops.
- **CPU**: Delta between successive `host_cpu_load_info` snapshots — avoids the first-read 100% spike. Raw ticks are stored as `previousCPULoad` for the next calculation.
- **RAM**: `active + wired + compressor` pages from `host_statistics64(HOST_VM_INFO64)`.
- **Storage**: `URL.resourceValues` on the boot volume root.
- **Battery**: Level and charging state from `IOPowerSources`; health % and cycle count from `AppleSmartBattery` IORegistry entry (`MaxCapacity / DesignCapacity`).

### Key constraints

- **Sandboxing is disabled** (`com.apple.security.app-sandbox = false` in `Info.plist`) — required for IOKit battery access. Do not enable the sandbox without adding appropriate entitlements or a helper process.
- **No Dock icon**: `LSUIElement = YES` in `Info.plist` hides the app from Dock and App Switcher.
- The preferences window uses a standalone `NSWindow` (not a SwiftUI `Sheet` or `WindowGroup`) to avoid stealing focus from the menu bar popover.
