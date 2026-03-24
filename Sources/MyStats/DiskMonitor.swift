import Foundation

struct DiskUsage {
    var free: Int64
    var total: Int64
    var used: Int64
    var percentage: Double
}

class DiskMonitor {
    static let shared = DiskMonitor()
    
    func getDiskUsage() -> DiskUsage? {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            
            if let capacity = values.volumeTotalCapacity,
               let available = values.volumeAvailableCapacity {
                
                let total = Int64(capacity)
                let free = Int64(available)
                let used = total - free
                let percentage = Double(used) / Double(total)
                
                return DiskUsage(free: free, total: total, used: used, percentage: percentage)
            }
        } catch {
            print("Error retrieving disk usage: \(error.localizedDescription)")
        }
        return nil
    }
}
