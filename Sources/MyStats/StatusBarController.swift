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

    // Shown when an external drive is below an announced alert threshold.
    private let externalBadge = DotView(color: NSColor(red: 0.95, green: 0.60, blue: 0.29, alpha: 1.0))

    // Layout Constants
    private let badgeGutter: CGFloat = 6         // room for the external-drive badge left of "F:"
    private let diskWidth: CGFloat = 68          // "F: 179.89 GB"
    private let dotSize: CGFloat = 4
    private let dotMargin: CGFloat = 4           // space around dot
    private let netWidth: CGFloat = 48           // "999 KB/s"

    // Vertical Layout
    private let topRowY: CGFloat = 11
    private let bottomRowY: CGFloat = 0
    private let rowHeight: CGFloat = 11

    init() {
        let totalWidth = badgeGutter + diskWidth + dotMargin + dotSize + dotMargin + netWidth
        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: 22))

        // --- External-drive alert badge (top-left, hidden until needed) ---
        externalBadge.frame = NSRect(x: 0, y: topRowY + (rowHeight - 5) / 2, width: 5, height: 5)
        externalBadge.isHidden = true
        addSubview(externalBadge)

        // --- Disk Section (Left) ---
        setupLabel(diskFreeLabel,
                   frame: NSRect(x: badgeGutter, y: topRowY, width: diskWidth, height: rowHeight),
                   align: .left)

        setupLabel(diskUsedLabel,
                   frame: NSRect(x: badgeGutter, y: bottomRowY, width: diskWidth, height: rowHeight),
                   align: .left)

        // --- Colored Dots (separator + direction indicator) ---
        let dotX = badgeGutter + diskWidth + dotMargin
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

    // internalAlert: the internal disk is below an announced threshold → F: turns red and bold.
    // externalAlert: some mounted external drive is → orange badge (F: itself is the internal disk).
    func update(diskFree: String, diskUsed: String, netUp: String, netDown: String,
                internalAlert: Bool, externalAlert: Bool) {
        diskFreeLabel.stringValue = diskFree
        diskFreeLabel.textColor = internalAlert ? .systemRed : .labelColor
        diskFreeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: internalAlert ? .bold : .regular)
        externalBadge.isHidden = !externalAlert
        diskUsedLabel.stringValue = diskUsed
        upValueLabel.stringValue = netUp
        downValueLabel.stringValue = netDown
    }
}

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusView!
    private var timer: Timer?
    private var alertTimer: Timer?

    // Live info rows in the dropdown (titles refreshed in menuNeedsUpdate).
    private var availableItem: NSMenuItem!         // accurate/smaller: df real free
    private var finderAvailableItem: NSMenuItem!   // Finder-consistent: importantUsage
    private var launchItem: NSMenuItem!
    private var externalHeader: NSMenuItem!        // "External Drives"; disk rows are inserted after it
    private var externalSeparator: NSMenuItem!
    private var externalRows: [NSMenuItem] = []
    private var notificationsItem: NSMenuItem!

    // Alerting
    private let configStore = AlertConfigStore()
    private let alerts = DiskAlerts()
    private var device: String?                    // model name, e.g. "Mac mini"; keys config "internal"
    private var externals: [ExternalVolume] = []
    private var internalStatus: DiskAlerts.Status?
    private var externalStatus: [String: DiskAlerts.Status] = [:]

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
        startAlerting()
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

        // --- External drives (rows rebuilt in menuNeedsUpdate; whole block hidden when none) ---
        externalHeader = NSMenuItem()
        externalHeader.attributedTitle = NSAttributedString(string: "External Drives", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor])
        externalHeader.isEnabled = false
        menu.addItem(externalHeader)

        externalSeparator = NSMenuItem.separator()
        menu.addItem(externalSeparator)

        // --- Notifications (submenu rebuilt in menuNeedsUpdate) ---
        notificationsItem = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        notificationsItem.submenu = NSMenu()
        menu.addItem(notificationsItem)

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

    // MARK: NSMenuDelegate — refresh readouts, drives, and the selection each time the dropdown opens.
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

        checkAlerts()
        rebuildExternalRows(in: menu)
        rebuildNotificationsMenu()
    }

    private func rebuildExternalRows(in menu: NSMenu) {
        externalRows.forEach { menu.removeItem($0) }
        externalRows = externals.map(externalRow)
        var index = menu.index(of: externalHeader) + 1
        for row in externalRows {
            menu.insertItem(row, at: index)
            index += 1
        }
        externalHeader.isHidden = externals.isEmpty
        externalSeparator.isHidden = externals.isEmpty
    }

    // Three lines: "Name        85%" / usage bar / "292.41 GB free of 2.00 TB · next alert 242 GB".
    // Drawn with an attributed title (not a custom view) so the row keeps native highlight and click.
    private func externalRow(_ vol: ExternalVolume) -> NSMenuItem {
        let status = externalStatus[vol.id]
        let alerting = status?.alerting == true
        let item = NSMenuItem(title: vol.name, action: #selector(openVolume(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = vol.url
        item.onStateImage = alerting ? dotImage(.systemRed) : nil
        item.state = alerting ? .on : .off

        let width: CGFloat = 270
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: width)]
        para.lineSpacing = 1
        let accent: NSColor = alerting ? .systemRed : .labelColor
        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: vol.name, attributes: [
            .font: NSFont.menuFont(ofSize: 0), .foregroundColor: accent, .paragraphStyle: para]))
        title.append(NSAttributedString(string: String(format: "\t%.0f%%\n", vol.usage.percentage * 100), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: alerting ? NSColor.systemRed : NSColor.secondaryLabelColor, .paragraphStyle: para]))
        let bar = NSTextAttachment()
        bar.image = barImage(fraction: vol.usage.percentage, width: width, color: alerting ? .systemRed : .systemGray)
        let barLine = NSMutableAttributedString(attachment: bar)
        barLine.append(NSAttributedString(string: "\n"))
        barLine.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: barLine.length))
        title.append(barLine)
        var sub = "\(formatDiskGB(Double(vol.usage.free))) free of \(formatCapacity(vol.usage.total))"
        if let next = status?.nextAlertGB { sub += " · next alert \(formatThreshold(next))" }
        title.append(NSAttributedString(string: sub, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
        item.attributedTitle = title
        return item
    }

    private func rebuildNotificationsMenu() {
        let sub = NSMenu()
        sub.autoenablesItems = false

        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(string: "Next alert", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor])
        header.isEnabled = false
        sub.addItem(header)

        var rows: [(String, DiskAlerts.Status)] = []
        if let s = internalStatus { rows.append((rootVolumeName(), s)) }
        rows += externals.compactMap { v in externalStatus[v.id].map { (v.name, $0) } }
        if rows.isEmpty {
            sub.addItem(infoItem("No rules for this Mac"))
        }
        for (name, status) in rows {
            let para = NSMutableParagraphStyle()
            para.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
            let value = status.nextAlertGB.map(formatThreshold) ?? "—"
            let item = NSMenuItem()
            item.attributedTitle = NSAttributedString(string: "\(name)\t\(value)", attributes: [
                .font: NSFont.menuFont(ofSize: 0), .paragraphStyle: para,
                .foregroundColor: status.alerting ? NSColor.systemRed : NSColor.labelColor])
            item.isEnabled = false
            sub.addItem(item)
        }

        sub.addItem(NSMenuItem.separator())
        let test = NSMenuItem(title: "Send Test to Slack", action: #selector(sendTest), keyEquivalent: "")
        test.target = self
        sub.addItem(test)
        let open = NSMenuItem(title: "Open Config…", action: #selector(openConfig), keyEquivalent: "")
        open.target = self
        open.isEnabled = FileManager.default.fileExists(atPath: AlertConfig.path)
        sub.addItem(open)

        sub.addItem(NSMenuItem.separator())
        var line = "Device: \(device ?? "…")"
        if let err = configStore.error { line += " · \(err)" }
        let notifier = SlackNotifier.shared
        if let problem = notifier.problem { line += " · \(problem)" } else { line += " · Slack ✓" }
        if notifier.pendingCount > 0 { line += " · \(notifier.pendingCount) pending" }
        sub.addItem(infoItem(line))

        notificationsItem.submenu = sub
    }

    private func infoItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        item.isEnabled = false
        return item
    }

    @objc private func selectDfMode() {
        UserDefaults.standard.set("real", forKey: "diskFreeMode")
        updateStatus()
    }

    @objc private func selectFinderMode() {
        UserDefaults.standard.set("finder", forKey: "diskFreeMode")
        updateStatus()
    }

    @objc private func openVolume(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AlertConfig.path))
    }

    @objc private func sendTest() {
        SlackNotifier.shared.flush(force: true)
        SlackNotifier.shared.send("🧪 \(device ?? "Mac") · MyStats 测试消息：Slack 通知正常。")
    }

    private func startMonitoring() {
        updateStatus()
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    // Thresholds are checked once a minute, on every mount/unmount, and whenever the menu opens.
    private func startAlerting() {
        DispatchQueue.global(qos: .utility).async {
            let model = DeviceInfo.modelName() ?? Host.current().localizedName ?? "Mac"
            DispatchQueue.main.async {
                self.device = model
                self.checkAlerts()
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            ws.addObserver(self, selector: #selector(checkAlerts), name: name, object: nil)
        }
        alertTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(checkAlerts), userInfo: nil, repeats: true)
        RunLoop.main.add(alertTimer!, forMode: .common)
    }

    @objc private func checkAlerts() {
        configStore.reloadIfChanged()
        externals = DiskMonitor.shared.externalVolumes()
        internalStatus = nil
        externalStatus = [:]
        if let config = configStore.config, let device {
            let margin = config.recoveryMarginGB
            if let rule = config.internal[device], let usage = DiskMonitor.shared.getDiskUsage() {
                internalStatus = alerts.evaluate(key: "internal", label: "内置盘", device: device,
                                                 rule: rule, usage: usage, margin: margin)
            }
            for vol in externals {
                guard let rule = config.external[vol.id] else { continue }
                externalStatus[vol.id] = alerts.evaluate(key: vol.id, label: vol.name, device: device,
                                                         rule: rule, usage: vol.usage, margin: margin)
            }
        }
        SlackNotifier.shared.flush()
        updateStatus()
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
        let internalAlert = internalStatus?.alerting == true
        let externalAlert = externalStatus.values.contains { $0.alerting }

        DispatchQueue.main.async {
            self.statusView.update(diskFree: dFree, diskUsed: dUsed, netUp: nUp, netDown: nDown,
                                   internalAlert: internalAlert, externalAlert: externalAlert)
        }
    }

    private func formatDiskGB(_ bytes: Double) -> String {
        // Decimal GB (÷10⁹) to match Finder / Settings → Storage / About This Mac.
        return String(format: "%.2f GB", bytes / 1_000_000_000)
    }

    private func formatCapacity(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 1000 ? String(format: "%.2f TB", gb / 1000) : String(format: "%.0f GB", gb)
    }

    private func formatThreshold(_ gb: Double) -> String {
        gb == gb.rounded() ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }

    private func rootVolumeName() -> String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Internal"
    }

    private func dotImage(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private func barImage(fraction: Double, width: CGFloat, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: width, height: 5), flipped: false) { rect in
            let track = NSRect(x: 0, y: 1, width: rect.width, height: 3)
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
            color.setFill()
            let fill = NSRect(x: 0, y: 1, width: rect.width * CGFloat(min(max(fraction, 0), 1)), height: 3)
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
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
