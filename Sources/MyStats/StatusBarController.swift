import AppKit
import ServiceManagement

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

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusView!
    private var timer: Timer?

    // Live info rows in the dropdown (titles refreshed in menuNeedsUpdate).
    private var availableItem: NSMenuItem!         // accurate/smaller: df real free
    private var finderAvailableItem: NSMenuItem!   // Finder-consistent: importantUsage
    private var launchItem: NSMenuItem!

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
        menu.delegate = self
        menu.autoenablesItems = false

        // --- Two selectable free-space modes (radio; the chosen one drives the menu bar F:/U:):
        //   "Available"        = df real free — smaller, accurate, always-stable (DEFAULT).
        //   "Finder Available" = importantUsage — exactly what Finder / Settings → Storage show.
        availableItem = NSMenuItem(title: "Available", action: #selector(selectDfMode), keyEquivalent: "")
        availableItem.target = self
        menu.addItem(availableItem)

        finderAvailableItem = NSMenuItem(title: "Finder Available", action: #selector(selectFinderMode), keyEquivalent: "")
        finderAvailableItem.target = self
        menu.addItem(finderAvailableItem)

        menu.addItem(NSMenuItem.separator())

        // --- Launch at Login (checkable) ---
        launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MyStats", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // Selected free-space mode. Default "real" = df real free (accurate). "finder" = importantUsage
    // (exactly what Finder / Settings → Storage show). The chosen mode drives the menu bar F:/U:.
    private var diskMode: String { UserDefaults.standard.string(forKey: "diskFreeMode") ?? "real" }

    private func selectedAvailableBytes(_ disk: DiskUsage) -> Int64 {
        diskMode == "finder" ? disk.freeIncludingPurgeable : disk.free
    }
    private func usedBytes(_ disk: DiskUsage) -> Int64 { disk.total - selectedAvailableBytes(disk) }

    // MARK: NSMenuDelegate — refresh both readouts and the selection each time the dropdown opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let disk = DiskMonitor.shared.getDiskUsage() {
            availableItem.title = "Available:  " + formatDiskGB(Double(disk.free))
            finderAvailableItem.title = "Finder Available:  " + formatDiskGB(Double(disk.freeIncludingPurgeable))
        } else {
            availableItem.title = "Available:  —"
            finderAvailableItem.title = "Finder Available:  —"
        }
        let finder = (diskMode == "finder")
        availableItem.state = finder ? .off : .on
        finderAvailableItem.state = finder ? .on : .off
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func selectDfMode() {
        UserDefaults.standard.set("real", forKey: "diskFreeMode")
        updateStatus()
    }

    @objc private func selectFinderMode() {
        UserDefaults.standard.set("finder", forKey: "diskFreeMode")
        updateStatus()
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
            // The selected mode drives both F: (available) and U: (used).
            dFree = "F: " + formatDiskGB(Double(selectedAvailableBytes(disk)))
            dUsed = "U: " + formatDiskGB(Double(usedBytes(disk)))
        }

        let nUp = formatNetSpeed(netSpeed.upload)
        let nDown = formatNetSpeed(netSpeed.download)

        DispatchQueue.main.async {
            self.statusView.update(diskFree: dFree, diskUsed: dUsed, netUp: nUp, netDown: nDown)
        }
    }

    private func formatDiskGB(_ bytes: Double) -> String {
        // Decimal GB (÷10⁹) to match Finder / Settings → Storage / About This Mac.
        return String(format: "%.2f GB", bytes / 1_000_000_000)
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

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("MyStats: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
