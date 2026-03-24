# MyStats

A lightweight, native macOS menu bar application to monitor Disk and Network usage.

## Features
- **Disk Usage**: Shows free and used disk space in GB (two-row layout).
- **Network Speed**: Shows real-time upload/download speeds, auto-scaling between B/s, KB/s, and MB/s.
- **Minimalist**: Uses native Swift and AppKit for maximum performance and minimum footprint.
- **Settings**: Simple "Launch at Login" option.

## Requirements
- macOS 13 (Ventura) or later
- Xcode Command Line Tools (for building from source)

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/Humsweet/MyStats.git
cd MyStats

# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Build the app
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

After building, move `MyStats.app` to `/Applications` and double-click to run.

> **Note**: Moving to `/Applications` is recommended for "Launch at Login" to work correctly due to macOS security restrictions.

## Usage
The status bar item displays a compact two-row view:

```
F: 179.89 GB  ● 512 KB/s
U: 300.11 GB  ● 128 KB/s
```

- Top row: Free disk space (F:) + upload speed (red dot indicator)
- Bottom row: Used disk space (U:) + download speed (blue dot indicator)
- Click the item to open the menu.
- Select "Settings" to enable/disable Launch at Login.
- Select "Quit" to exit.

## Technical Details
- Built with Swift 5.9, targeting macOS 13+.
- Uses `getifaddrs` for network monitoring (low-level BSD socket API), excluding loopback interfaces.
- Uses `SMAppService` for modern login item management.
- Updates every 1 second via a `Timer` on the main run loop.
