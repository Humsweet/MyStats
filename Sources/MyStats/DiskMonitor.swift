import Foundation

struct DiskUsage {
    var free: Int64                  // volumeAvailableCapacityKey (df-style, truly free)
    var freeIncludingPurgeable: Int64 // volumeAvailableCapacityForImportantUsageKey (Finder-style, free + purgeable)
    var total: Int64
    var used: Int64
    var percentage: Double
}

class DiskMonitor {
    static let shared = DiskMonitor()

    func getDiskUsage() -> DiskUsage? {
        let fileURL = URL(fileURLWithPath: "/")
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
            print("Error retrieving disk usage: \(error.localizedDescription)")
        }
        return nil
    }
}
