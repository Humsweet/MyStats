import Foundation
import SystemConfiguration

struct NetworkSpeed {
    var upload: Double // bytes per second
    var download: Double // bytes per second
}

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private var prevInBytes: UInt64 = 0
    private var prevOutBytes: UInt64 = 0
    private var lastCheckTime: Date?
    
    // Using a simpler approach: get global counts first, or iterate interfaces.
    // Iterating interfaces is better to exclude loopback.
    
    func getNetworkUsage() -> (inBytes: UInt64, outBytes: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        
        var totalInBytes: UInt64 = 0
        var totalOutBytes: UInt64 = 0
        
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            // let name = String(cString: interface.ifa_name) // Unused
            
            // Filter loopback and inactive interfaces
            if (interface.ifa_flags & UInt32(IFF_UP)) == UInt32(IFF_UP) &&
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                
                if let data = interface.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    // Only count link layer stats (AF_LINK) to avoid double counting IP layer stats if present
                    if interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                        totalInBytes += UInt64(networkData.pointee.ifi_ibytes)
                        totalOutBytes += UInt64(networkData.pointee.ifi_obytes)
                    }
                }
            }
            ptr = interface.ifa_next
        }
        
        return (totalInBytes, totalOutBytes)
    }
    
    func checkSpeed() -> NetworkSpeed {
        let (currentIn, currentOut) = getNetworkUsage()
        let now = Date()
        
        guard let lastTime = lastCheckTime else {
            prevInBytes = currentIn
            prevOutBytes = currentOut
            lastCheckTime = now
            return NetworkSpeed(upload: 0, download: 0)
        }
        
        let timeDiff = now.timeIntervalSince(lastTime)
        if timeDiff == 0 { return NetworkSpeed(upload: 0, download: 0) }
        
        // Handle overflow (though UInt64 is large, reboot might reset counters)
        let downloadBytes = currentIn >= prevInBytes ? Double(currentIn - prevInBytes) : 0
        let uploadBytes = currentOut >= prevOutBytes ? Double(currentOut - prevOutBytes) : 0
        
        let downloadSpeed = downloadBytes / timeDiff
        let uploadSpeed = uploadBytes / timeDiff
        
        prevInBytes = currentIn
        prevOutBytes = currentOut
        lastCheckTime = now
        
        return NetworkSpeed(upload: uploadSpeed, download: downloadSpeed)
    }
}
