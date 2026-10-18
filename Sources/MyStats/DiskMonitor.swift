import Foundation

struct DiskUsage {
    var free: Int64                  // volumeAvailableCapacityKey (df-style, truly free)
    var freeIncludingPurgeable: Int64 // volumeAvailableCapacityForImportantUsageKey (Finder-style, free + purgeable)
    var total: Int64
    var used: Int64
    var percentage: Double
}

// A mounted external volume. Identified by its volume UUID so per-disk rules survive renames
// and moving the drive to another Mac; falls back to the name when the filesystem has no UUID.
struct ExternalVolume {
    var url: URL
    var name: String
    var id: String
    var usage: DiskUsage
}

class DiskMonitor {
    static let shared = DiskMonitor()

    func getDiskUsage() -> DiskUsage? {
        usage(at: URL(fileURLWithPath: "/"))
    }

    // Fresh URL every call, so no stale resource-value cache.
    func usage(at url: URL) -> DiskUsage? {
        let fileURL = URL(fileURLWithPath: url.path)
        do {
            let keys: Set<URLResourceKey> = [
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ]
            let values = try fileURL.resourceValues(forKeys: keys)

            if let capacity = values.volumeTotalCapacity,
               let available = values.volumeAvailableCapacity {

                let total = Int64(capacity)
                let free = Int64(available)
                let freeIncludingPurgeable = Int64(values.volumeAvailableCapacityForImportantUsage ?? Int64(available))
                let used = total - free
                let percentage = Double(used) / Double(total)

                return DiskUsage(free: free, freeIncludingPurgeable: freeIncludingPurgeable,
                                 total: total, used: used, percentage: percentage)
            }
        } catch {
            print("Error retrieving disk usage for \(url.path): \(error.localizedDescription)")
        }
        return nil
    }

    // Local, writable, non-internal volumes. Read-only excludes mounted .dmg installers;
    // non-local excludes network shares.
    func externalVolumes() -> [ExternalVolume] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsLocalKey, .volumeIsReadOnlyKey,
                                      .volumeNameKey, .volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsInternal == false, v.volumeIsLocal == true, v.volumeIsReadOnly == false,
                  let usage = usage(at: url) else { return nil }
            let name = v.volumeName ?? url.lastPathComponent
            return ExternalVolume(url: url, name: name, id: v.volumeUUIDString ?? name, usage: usage)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
