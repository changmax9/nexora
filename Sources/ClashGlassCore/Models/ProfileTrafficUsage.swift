import Foundation

/// Subscription quota or an imported YAML snapshot, independent of device traffic.
public struct ProfileTrafficUsage: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case subscription
        case configuration
    }

    public let uploadBytes: Int64
    public let downloadBytes: Int64
    public let totalBytes: Int64
    public let updatedAt: Date
    public let source: Source?
    public let reportedRemainingBytes: Int64?

    public init?(subscriptionUserInfo: String?, updatedAt: Date = Date(), source: Source = .subscription) {
        guard let subscriptionUserInfo else { return nil }
        var counters: [String: Int64] = [:]
        for field in subscriptionUserInfo.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["upload", "download", "total"].contains(key) else { continue }
            guard counters[key] == nil,
                  let value = Int64(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  value >= 0 else { return nil }
            counters[key] = value
        }
        guard let upload = counters["upload"],
              let download = counters["download"],
              let total = counters["total"] else { return nil }
        uploadBytes = upload
        downloadBytes = download
        totalBytes = total
        self.source = source
        reportedRemainingBytes = nil
        // Match the registry's ISO 8601 precision across save/load cycles.
        self.updatedAt = Date(timeIntervalSince1970: updatedAt.timeIntervalSince1970.rounded(.down))
    }

    /// Some YAML files report only a remaining balance in an informational node.
    /// There is no total quota from which to derive a percentage.
    public init?(remainingBytes: Int64, updatedAt: Date) {
        guard remainingBytes >= 0 else { return nil }
        uploadBytes = 0
        downloadBytes = 0
        totalBytes = 0
        reportedRemainingBytes = remainingBytes
        source = .configuration
        self.updatedAt = Date(timeIntervalSince1970: updatedAt.timeIntervalSince1970.rounded(.down))
    }

    public var remainingBytes: Int64? {
        guard totalBytes > 0 else { return reportedRemainingBytes }
        // Subtract separately so even Int64.max counters cannot overflow.
        let afterUpload = totalBytes - min(totalBytes, max(0, uploadBytes))
        return afterUpload - min(afterUpload, max(0, downloadBytes))
    }

    public var remainingFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return remainingBytes.map { Double($0) / Double(totalBytes) }
    }

    public var remainingGigabytes: Double? {
        remainingBytes.map { Double($0) / 1_073_741_824 }
    }
}
