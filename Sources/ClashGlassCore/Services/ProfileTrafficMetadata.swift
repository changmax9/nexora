import Foundation
import Yams

/// Reads explicit quota metadata without treating ordinary server names as usage.
enum ProfileTrafficMetadata {
    static func usage(in yaml: String, updatedAt: Date) -> ProfileTrafficUsage? {
        guard let config = try? Yams.load(yaml: yaml) as? [String: Any] else { return nil }
        if let header = config.first(where: { $0.key.lowercased() == "subscription-userinfo" })?.value as? String,
           let usage = ProfileTrafficUsage(subscriptionUserInfo: header, updatedAt: updatedAt, source: .configuration) {
            return usage
        }

        let proxies = config["proxies"] as? [[String: Any]] ?? []
        let balances = Set(proxies.compactMap { proxy -> Int64? in
            guard let name = proxy["name"] as? String else { return nil }
            return remainingBytes(in: name)
        })
        // Multiple subscriptions in one YAML must not produce an arbitrary balance.
        guard balances.count == 1, let bytes = balances.first else { return nil }
        return ProfileTrafficUsage(remainingBytes: bytes, updatedAt: updatedAt)
    }

    private static func remainingBytes(in name: String) -> Int64? {
        let pattern = #"(?i)^\s*(?:剩[余餘]流量|剩[余餘]可用流量|remaining\s+(?:traffic|data)|(?:traffic|data)\s+(?:remaining|left))\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*(B|[KMGT]i?B)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let valueRange = Range(match.range(at: 1), in: name),
              let unitRange = Range(match.range(at: 2), in: name),
              let value = Double(name[valueRange]), value.isFinite, value >= 0 else { return nil }
        let unit = name[unitRange].uppercased()
        let exponent: Double
        switch unit {
        case "B": exponent = 0
        case "KB", "KIB": exponent = 1
        case "MB", "MIB": exponent = 2
        case "GB", "GIB": exponent = 3
        case "TB", "TIB": exponent = 4
        default: return nil
        }
        let bytes = value * pow(1_024, exponent)
        guard bytes.isFinite, bytes < Double(Int64.max) else { return nil }
        return Int64(bytes.rounded(.down))
    }
}
