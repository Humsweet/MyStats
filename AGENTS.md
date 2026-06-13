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

The app is pure AppKit — no SwiftUI, no settings window. All interaction is the status-bar item plus its click-down dropdown `NSMenu`.

**Key files:**

- `StatusBarController.swift` — owns the `NSStatusItem`, drives the 1-second `Timer` (`updateStatus`), and builds + maintains the dropdown `NSMenu`. It is the menu's `NSMenuDelegate`: `menuNeedsUpdate(_:)` refreshes the live disk readouts and the radio selection each time the menu opens. Also contains `StatusView`, the custom `NSView` drawn inside the status-bar button.
- `DiskMonitor.swift` — reads disk stats via `URLResourceValues` (fresh `URL` each call, so no stale resource-value cache). Returns `free` (`volumeAvailableCapacityKey` — truly-unallocated blocks, like `df`; smaller, stable) and `freeIncludingPurgeable` (`volumeAvailableCapacityForImportantUsageKey` — exactly what Finder / Settings → Storage show; free + purgeable).
- `NetworkMonitor.swift` — reads per-interface byte counters via `getifaddrs`, skipping loopback. Computes upload/download speed as delta over elapsed time. First call always returns 0.

**Status bar layout (StatusView):** Two rows × two columns. Left column: disk free `F:` (top) and disk used `U:` (bottom). Right column: upload speed (top) and download speed (bottom). Rows are separated by colored dots (red = up, blue = down). Disk values are decimal GB (÷10⁹), to match Finder/Storage.

**Dropdown menu (built in `setupMenu`, refreshed in `menuNeedsUpdate`):**
- Two selectable, mutually-exclusive free-space modes (radio, checkmark on the active one). The chosen mode drives the status bar's `F:` (available) and `U:` (= total − available):
  - **`Available`** — `free` (df). The smaller, accurate, always-stable figure. **Default.**
  - **`Finder Available`** — `freeIncludingPurgeable` (importantUsage). Mirrors Finder/Storage exactly; if Finder is briefly wrong at boot (before its purgeable scan completes) this is wrong identically — consistency with Finder by design. See the memory note `disk-available-semantics` for why the deep "System Data" scan can't be triggered by a third-party app.
- `Launch at Login` — checkable; toggling calls `SMAppService.mainApp` register/unregister; its checkmark reflects the live `SMAppService.mainApp.status`.
- `Quit MyStats` (⌘Q).

**Persistence:** plain `UserDefaults` (no `@AppStorage`):
- `diskFreeMode` — `"real"` (default → `Available`/df) or `"finder"` (→ `Finder Available`/importantUsage). Read via `?? "real"`, so an absent key means df.
- Launch-at-login state is not stored by us — it's read live from `SMAppService.mainApp.status`.

**Bundle identity:** `com.hanyuyang.MyStats` (set in `build_app.sh`). The SPM build itself produces a plain Mach-O binary; the `.app` bundle with `Info.plist` is only created by the shell script. Note: a raw `.build/...` binary run directly does **not** use the `com.hanyuyang.MyStats` UserDefaults domain (only the bundled `.app` does).
