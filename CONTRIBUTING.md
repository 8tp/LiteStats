# Contributing to LiteStats

Thanks for your interest in contributing! LiteStats is a small, focused project and contributions of all kinds are welcome.

## Reporting Bugs

Open a [GitHub issue](../../issues/new) with:

- Your macOS version and Mac model
- Steps to reproduce the problem
- What you expected vs. what happened
- Any relevant screenshots or console logs

## Requesting Features

Open a [GitHub issue](../../issues/new) describing the feature and why it would be useful. Please check existing issues first to avoid duplicates.

## Submitting Pull Requests

1. Fork the repo and create a branch from `master`
2. Make your changes
3. Test by building and running the app (`⌘R` in Xcode)
4. Open a PR against `master` with a clear description of what changed and why

### Code style

- Follow standard Swift conventions (camelCase, etc.)
- Keep the project **dependency-free** — no Swift packages, CocoaPods, or Carthage
- Match the existing code style in the file you're editing
- Keep changes focused — one feature or fix per PR

### Build & test

There is no automated test suite. To verify your changes:

```sh
xcodebuild -project LiteStats.xcodeproj -scheme LiteStats -configuration Debug build
```

Or open `LiteStats.xcodeproj` in Xcode and press `⌘R`.

## Architecture Overview

If you're not sure where to make a change, here's a quick guide:

| What you want to change | Where to look |
|---|---|
| Add or modify a system metric | `StatsModel.swift` |
| Change the popover UI | `ContentView.swift` |
| Change the preferences panel | `PreferencesView.swift` |
| Change app lifecycle or menu bar setup | `LiteStatsApp.swift` |

See the [README](README.md#architecture) for more detail.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
