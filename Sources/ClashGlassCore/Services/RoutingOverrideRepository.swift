import Foundation
import Yams

public enum RoutingPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case vpn
    case direct

    public var id: Self { self }

    var title: String {
        switch self {
        case .vpn: "VPN"
        case .direct: "Direct"
        }
    }

    func ruleTarget(vpnTarget: String) -> String {
        switch self {
        case .vpn: vpnTarget
        case .direct: "DIRECT"
        }
    }
}

public struct RoutingOverride: Codable, Equatable, Identifiable, Sendable {
    public var id: String { domain }
    public let domain: String
    public let policy: RoutingPolicy

    public init(domain: String, policy: RoutingPolicy) {
        self.domain = domain
        self.policy = policy
    }
}

enum RoutingInputError: Error, LocalizedError {
    case invalidDomain

    var errorDescription: String? {
        switch self {
        case .invalidDomain:
            "Enter a valid public URL or domain."
        }
    }
}

enum RoutingInputNormalizer {
    static func domain(from input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RoutingInputError.invalidDomain
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              var host = components.host?.lowercased() else {
            throw RoutingInputError.invalidDomain
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4Literal = labels.count == 4
            && labels.allSatisfy { label in
                guard let octet = Int(label) else {
                    return false
                }
                return (0...255).contains(octet)
            }
        guard labels.count >= 2,
              !isIPv4Literal,
              labels.allSatisfy({ label in
                  !label.isEmpty
                      && label.count <= 63
                      && label.first != "-"
                      && label.last != "-"
                      && label.allSatisfy { character in
                          character.isLetter || character.isNumber || character == "-"
                      }
              }) else {
            throw RoutingInputError.invalidDomain
        }
        return host
    }
}

enum RoutingVPNTargetResolver {
    static func target(from yaml: String) -> String? {
        guard let configuration = try? Yams.compose(yaml: yaml),
              let groups = MihomoYAMLValue.value("proxy-groups", in: configuration)?.sequence else {
            return nil
        }
        let selector = groups.first { group in
            MihomoYAMLValue.value("type", in: group)?.string?.lowercased() == "select"
                && MihomoYAMLValue.value("name", in: group)?.string?.isEmpty == false
        }
        return MihomoYAMLValue.value("name", in: selector)?.string
    }
}

struct RoutingOverrideRepository: Sendable {
    let rootURL: URL

    private var registryURL: URL {
        rootURL.appendingPathComponent("routing-overrides.json")
    }

    init(rootURL: URL = ManagedProfileRepository.defaultRootURL()) {
        self.rootURL = rootURL
    }

    func overrides(profileID: ManagedProfile.ID) throws -> [RoutingOverride] {
        try loadRegistry()[profileID.uuidString, default: []]
            .sorted { $0.domain < $1.domain }
    }

    func upsert(
        domain: String,
        policy: RoutingPolicy,
        profileID: ManagedProfile.ID
    ) throws {
        var registry = try loadRegistry()
        var values = registry[profileID.uuidString, default: []]
        values.removeAll { $0.domain == domain }
        values.append(RoutingOverride(domain: domain, policy: policy))
        registry[profileID.uuidString] = values.sorted { $0.domain < $1.domain }
        try saveRegistry(registry)
    }

    func remove(domain: String, profileID: ManagedProfile.ID) throws {
        var registry = try loadRegistry()
        registry[profileID.uuidString, default: []].removeAll { $0.domain == domain }
        try saveRegistry(registry)
    }

    func removeProfile(_ profileID: ManagedProfile.ID) throws {
        var registry = try loadRegistry()
        registry.removeValue(forKey: profileID.uuidString)
        try saveRegistry(registry)
    }

    private func loadRegistry() throws -> [String: [RoutingOverride]] {
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            return [:]
        }
        return try JSONDecoder().decode(
            [String: [RoutingOverride]].self,
            from: Data(contentsOf: registryURL)
        )
    }

    private func saveRegistry(_ registry: [String: [RoutingOverride]]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
    }
}

enum RoutingRuntimeError: Error, LocalizedError {
    case restartFailed(String)

    var errorDescription: String? {
        switch self {
        case let .restartFailed(message):
            message
        }
    }
}
