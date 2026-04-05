This file provides guidance to AI Agents when working with code in this repository.

## Commands

```bash
# Debug build (fast, for development)
swift build

# Release build
swift build -c release

# Build .app bundle (release build + Info.plist + bundle structure)
./scripts/build_app.sh
# Output: MyStats.app at repo root
```

No test targets exist in this project.

## Architecture

MyStats is a macOS menu bar app built with Swift Package Manager (no Xcode project). It targets macOS 13+ and produces a headless `NSApplication` with `LSUIElement = true` (no Dock icon).

**Startup chain:** `main.swift` → `AppDelegate` → `StatusBarController`

**Key files:**

- `StatusBarController.swift` — owns the `NSStatusItem`, drives the 1-second `Timer`, builds the right-click menu, and hosts `SettingsView` (SwiftUI) in a plain `NSWindow`. Also contains `StatusView` (the custom `NSView` rendered inside the status bar button) and `SettingsView`.
- `DiskMonitor.swift` — reads disk stats via `URLResourceValues`. Returns both `free` (truly free blocks, like `df`) and `freeIncludingPurgeable` (Finder-style, includes local snapshots and caches). Which value is displayed is controlled by the `diskFreeMode` UserDefaults key (`"real"` or `"finder"`).
- `NetworkMonitor.swift` — reads per-interface byte counters via `getifaddrs`, skipping loopback. Computes upload/download speed as delta over elapsed time. First call always returns 0.

**Status bar layout (StatusView):** Two rows × two columns. Left column: disk free (top) and disk used (bottom). Right column: upload speed (top) and download speed (bottom). Rows are separated by colored dots (red = up, blue = down).

**Settings persistence:** `@AppStorage` / `UserDefaults` keys:
- `launchAtLogin` — bool, wired to `SMAppService.mainApp`
- `diskFreeMode` — `"real"` (default) or `"finder"`

**Bundle identity:** `com.hanyuyang.MyStats` (set in `build_app.sh`). The SPM build itself produces a plain Mach-O binary; the `.app` bundle with `Info.plist` is only created by the shell script.
