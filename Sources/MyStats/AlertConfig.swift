import Foundation

// "Alert once free space drops below `belowGB`, then again every further `everyGB`."
// Without `everyGB` the rule fires only at `belowGB`.
struct AlertRule: Codable, Equatable {
    var name: String?
    var belowGB: Double
    var everyGB: Double?

    // Thresholds in GB, highest first: below, below − every, below − 2·every, … (all > 0).
    var levels: [Double] {
        guard let step = everyGB, step > 0 else { return belowGB > 0 ? [belowGB] : [] }
        return Array(stride(from: belowGB, to: 0, by: -step))
    }
}

// One file shared by every Mac through dotfiles. Internal disks are keyed by the machine's model
// name ("Mac mini", "MacBook Air", "MacBook Pro"); external disks by volume UUID, so a drive's rule
// follows it to whichever Mac it is plugged into.
struct AlertConfig: Codable {
    var `internal`: [String: AlertRule] = [:]
    var external: [String: AlertRule] = [:]
    var recoveryMarginGB: Double = 2

    static let path = NSHomeDirectory() + "/dotfiles/apps/mystats/config.json"
}

// Reloads the config file whenever its modification date changes, so an edit — local, or pulled
// in by dotfiles sync from another Mac — takes effect on the next check without restarting.
final class AlertConfigStore {
    private(set) var config: AlertConfig?
    private(set) var error: String?
    private var loadedModDate: Date?

    func reloadIfChanged() {
        let modDate = (try? FileManager.default.attributesOfItem(atPath: AlertConfig.path))?[.modificationDate] as? Date
        guard let modDate else {
            config = nil
            loadedModDate = nil
            error = "Config not found"
            return
        }
        guard modDate != loadedModDate else { return }
        loadedModDate = modDate
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: AlertConfig.path))
            config = try JSONDecoder().decode(AlertConfig.self, from: data)
            error = nil
        } catch {
            config = nil
            self.error = "Config invalid"
            print("Cannot parse \(AlertConfig.path): \(error)")
        }
    }
}

enum DeviceInfo {
    // Marketing model name, e.g. "Mac mini". hw.model only gives "Mac16,10", so ask system_profiler.
    static func modelName() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hw = (json["SPHardwareDataType"] as? [[String: Any]])?.first else { return nil }
        return hw["machine_name"] as? String
    }
}
