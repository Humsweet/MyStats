import AppKit
import ServiceManagement
import SwiftUI

// Small colored dot indicator
class DotView: NSView {
    init(color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}

// Custom View for Status Bar — "F: XX.XX GB ● XX KB/s" style
class StatusView: NSView {
    private let diskFreeLabel = NSTextField()
    private let diskUsedLabel = NSTextField()

    private let upDot = DotView(color: NSColor(red: 0.95, green: 0.30, blue: 0.35, alpha: 1.0))
    private let downDot = DotView(color: NSColor(red: 0.25, green: 0.52, blue: 1.0, alpha: 1.0))

    private let upValueLabel = NSTextField()
    private let downValueLabel = NSTextField()

    // Layout Constants
    private let diskWidth: CGFloat = 68          // "F: 179.89 GB"
    private let dotSize: CGFloat = 4
    private let dotMargin: CGFloat = 4           // space around dot
    private let netWidth: CGFloat = 48           // "999 KB/s"

    // Vertical Layout
    private let topRowY: CGFloat = 11
    private let bottomRowY: CGFloat = 0
    private let rowHeight: CGFloat = 11

    init() {
        let totalWidth = diskWidth + dotMargin + dotSize + dotMargin + netWidth
        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: 22))

        // --- Disk Section (Left) ---
        setupLabel(diskFreeLabel,
                   frame: NSRect(x: 0, y: topRowY, width: diskWidth, height: rowHeight),
                   align: .left)

        setupLabel(diskUsedLabel,
                   frame: NSRect(x: 0, y: bottomRowY, width: diskWidth, height: rowHeight),
                   align: .left)

        // --- Colored Dots (separator + direction indicator) ---
        let dotX = diskWidth + dotMargin
        upDot.frame = NSRect(x: dotX, y: topRowY + (rowHeight - dotSize) / 2, width: dotSize, height: dotSize)
        addSubview(upDot)

        downDot.frame = NSRect(x: dotX, y: bottomRowY + (rowHeight - dotSize) / 2, width: dotSize, height: dotSize)
        addSubview(downDot)

        // --- Network Section (Right) ---
        let netX = dotX + dotSize + dotMargin
        setupLabel(upValueLabel,
                   frame: NSRect(x: netX, y: topRowY, width: netWidth, height: rowHeight),
                   align: .right)

        setupLabel(downValueLabel,
                   frame: NSRect(x: netX, y: bottomRowY, width: netWidth, height: rowHeight),
                   align: .right)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLabel(_ label: NSTextField, frame: NSRect, align: NSTextAlignment) {
        label.frame = frame
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = align
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        label.textColor = .labelColor
        addSubview(label)
    }

    func update(diskFree: String, diskUsed: String, netUp: String, netDown: String) {
        diskFreeLabel.stringValue = diskFree
        diskUsedLabel.stringValue = diskUsed
        upValueLabel.stringValue = netUp
        downValueLabel.stringValue = netDown
    }
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var statusView: StatusView!
    private var timer: Timer?
    private var settingsWindowController: NSWindowController?
    
    override init() {
        super.init()
        
        // Initialize status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Setup Custom View
        statusView = StatusView()
        
        if let button = statusItem.button {
            button.addSubview(statusView)
            
            // Explicitly set the length of the status item to match our view
            // This prevents jitter and ensures the click area is correct.
            statusItem.length = statusView.frame.width
        }
        
        setupMenu()
        startMonitoring()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func startMonitoring() {
        updateStatus()
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    @objc private func updateStatus() {
        let netSpeed = NetworkMonitor.shared.checkSpeed()
        let diskUsage = DiskMonitor.shared.getDiskUsage()

        var dFree = "F: —"
        var dUsed = "U: —"

        if let disk = diskUsage {
            let useFinderStyle = UserDefaults.standard.string(forKey: "diskFreeMode") == "finder"
            let freeBytes = useFinderStyle ? disk.freeIncludingPurgeable : disk.free
            dFree = "F: " + formatDiskGB(Double(freeBytes))
            dUsed = "U: " + formatDiskGB(Double(disk.used))
        }

        let nUp = formatNetSpeed(netSpeed.upload)
        let nDown = formatNetSpeed(netSpeed.download)

        DispatchQueue.main.async {
            self.statusView.update(diskFree: dFree, diskUsed: dUsed, netUp: nUp, netDown: nDown)
        }
    }

    private func formatDiskGB(_ bytes: Double) -> String {
        let gb = bytes / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.2f GB", gb)
    }

    private func formatNetSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
        }
    }
    
    @objc private func openSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.center()
            window.title = "Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            settingsWindowController = NSWindowController(window: window)
        }
        
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

struct SettingsView: View {
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("diskFreeMode") var diskFreeMode: String = "real"
    @State private var statusMessage: String = ""
    @State private var diskUsage: DiskUsage? = nil
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MyStats Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            // --- Disk Free Space Mode ---
            VStack(alignment: .leading, spacing: 8) {
                Text("Free Space Display")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 6) {
                    diskModeRow(
                        mode: "real",
                        label: "Real Free (df style)",
                        subtitle: "Truly unoccupied blocks",
                        value: diskUsage.map { formatGB(Double($0.free)) } ?? "—"
                    )
                    diskModeRow(
                        mode: "finder",
                        label: "Finder Style",
                        subtitle: "Includes purgeable (local snapshots, caches)",
                        value: diskUsage.map { formatGB(Double($0.freeIncludingPurgeable)) } ?? "—"
                    )
                }
            }

            Divider()

            // --- Launch at Login ---
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLoginItem(enabled: newValue)
                }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Spacer()

            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .frame(width: 320, height: 280)
        .onAppear {
            checkLoginItemStatus()
            diskUsage = DiskMonitor.shared.getDiskUsage()
        }
        .onReceive(timer) { _ in
            diskUsage = DiskMonitor.shared.getDiskUsage()
        }
    }

    @ViewBuilder
    private func diskModeRow(mode: String, label: String, subtitle: String, value: String) -> some View {
        Button(action: { diskFreeMode = mode }) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: diskFreeMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(diskFreeMode == mode ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(diskFreeMode == mode ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatGB(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
    }

    private func checkLoginItemStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered { return }
                try SMAppService.mainApp.unregister()
            }
            statusMessage = ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
