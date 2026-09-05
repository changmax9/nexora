import Foundation

struct TrafficUsageTotals: Equatable, Sendable {
    static let zero = TrafficUsageTotals(uploadBytes: 0, downloadBytes: 0)

    let uploadBytes: Int
    let downloadBytes: Int

    init(uploadBytes: Int, downloadBytes: Int) {
        self.uploadBytes = max(0, uploadBytes)
        self.downloadBytes = max(0, downloadBytes)
    }

    var hasTraffic: Bool { uploadBytes > 0 || downloadBytes > 0 }

    var uploadFraction: Double? {
        guard hasTraffic else { return nil }
        // Convert before adding so large cumulative counters cannot overflow Int.
        return Double(uploadBytes) / (Double(uploadBytes) + Double(downloadBytes))
    }

    var downloadFraction: Double? {
        guard hasTraffic else { return nil }
        return Double(downloadBytes) / (Double(uploadBytes) + Double(downloadBytes))
    }
}
