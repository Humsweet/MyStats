# MyStats

A lightweight, native macOS menu bar application to monitor Disk and Network usage.

## Features
- **Disk Usage**: Shows SSD percentage usage.
- **Network Speed**: Shows real-time Upload/Download speeds.
- **Minimalist**: Uses native Swift and AppKit for maximum performance and minimum footprint.
- **Settings**: Simple "Launch at Login" option.

## Installation
1. Move `MyStats.app` to your `/Applications` folder.
   > **Note**: Moving to `/Applications` is recommended for "Launch at Login" to work correctly due to macOS security restrictions.
2. Double-click to run.

## Usage
- Look for the status bar item: `SSD 50% ⬆1KB ⬇2KB`
- Click the item to open the menu.
- Select "Settings" to enable/disable Launch at Login.
- Select "Quit" to exit.

## Technical Details
- Built with Swift 5.9.
- Uses `getifaddrs` for network monitoring (low level BSD socket API).
- Uses `SMAppService` for modern login item management.
