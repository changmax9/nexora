import Foundation
import Yams

public enum RoutingPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case vpn
    case customNode
    case direct

    public var id: Self { self }
}

public struct RoutingOverride: Codable, Equatable, Identifiable, Sendable {
    public var id: String { domain }
    public let domain: String
    public let policy: RoutingPolicy
    public let proxyName: String?

    public init(domain: String, policy: RoutingPolicy, proxyName: String? = nil) {
        self.domain = domain
        self.policy = policy
        let trimmed = proxyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.proxyName = (policy == .customNode && trimmed?.isEmpty == false) ? trimmed : nil
    }

    func resolvedRuleTarget(vpnTarget: String?) -> String? {
        switch policy {
        case .vpn:
            guard let vpnTarget, !vpnTarget.isEmpty else { return nil }
            return vpnTarget
        case .direct:
            return "DIRECT"
        case .customNode:
            guard let proxyName, !proxyName.isEmpty else { return nil }
            return proxyName
        }
    }
}

public struct RoutingProxyTarget: Identifiable, Equatable, Sendable {
    public var id: String { "\(isGroup ? "group" : "node"):\(name)" }
    public let name: String
    public let isGroup: Bool
    public let latency: Int?
    public let region: String

    public init(name: String, isGroup: Bool, latency: Int? = nil, region: String = "Proxy") {
        self.name = name
        self.isGroup = isGroup
        self.latency = latency
        self.region = region
    }
}

enum RoutingOverrideTargetBridge {
    static let groupPrefix = "NexoraRoute-"

    static func bridgeGroupName(for target: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in target.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return "\(groupPrefix)\(String(format: "%016llx", hash).prefix(8))"
    }

    static func group(named name: String, target: String, fromProvider: Bool) -> Node {
        var group: Node = ["name": Node(name, Tag(.str)), "type": "select"]
        group["hidden"] = Node("true", Tag(.bool))
        if fromProvider {
            // Mihomo splits provider filters on backticks before compiling the regex.
            let literal = NSRegularExpression.escapedPattern(for: target)
                .replacingOccurrences(of: "`", with: #"\x60"#)
            group["include-all-providers"] = Node("true", Tag(.bool))
            group["filter"] = Node("^\(literal)$", Tag(.str), .singleQuoted)
            group["empty-fallback"] = Node("REJECT", Tag(.str))
        } else {
            group["proxies"] = Node([Node(target, Tag(.str), .singleQuoted)], .implicit, .block)
        }
        return group
    }
}

enum RoutingProxyTargetCatalog {
    private static let excludedNames: Set<String> = [
        "DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL",
    ]

    static func staticTargets(fromYAML yaml: String) -> [RoutingProxyTarget] {
        guard let configuration = try? Yams.compose(yaml: yaml) else {
            return []
        }
        var seen = Set<String>()
        var nodes: [RoutingProxyTarget] = []
        var groups: [RoutingProxyTarget] = []

        if let proxies = MihomoYAMLValue.value("proxies", in: configuration)?.sequence {
            for item in proxies {
                guard let name = MihomoYAMLValue.value("name", in: item)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    isSelectableTarget(name),
                    seen.insert(name).inserted else {
                    continue
                }
                nodes.append(RoutingProxyTarget(
                    name: name,
                    isGroup: false,
                    latency: nil,
                    region: MihomoAPIDecoder.regionCode(from: name)
                ))
            }
        }

        if let groupItems = MihomoYAMLValue.value("proxy-groups", in: configuration)?.sequence {
            for item in groupItems {
                if MihomoYAMLValue.value("hidden", in: item)?.bool == true {
                    continue
                }
                guard let name = MihomoYAMLValue.value("name", in: item)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    isSelectableTarget(name),
                    seen.insert(name).inserted else {
                    continue
                }
                groups.append(RoutingProxyTarget(
                    name: name,
                    isGroup: true,
                    latency: nil,
                    region: MihomoAPIDecoder.regionCode(from: name)
                ))
            }
        }

        return nodes + groups
    }

    static func mergedTargets(
        staticTargets: [RoutingProxyTarget],
        liveGroups: [ProxyGroup]
    ) -> [RoutingProxyTarget] {
        var liveNodesByName: [String: RoutingProxyTarget] = [:]
        var liveNodeOrder: [String] = []
        var liveGroupsByName: [String: RoutingProxyTarget] = [:]
        var liveGroupOrder: [String] = []

        for group in liveGroups {
            if isSelectableTarget(group.name), liveGroupsByName[group.name] == nil {
                liveGroupsByName[group.name] = RoutingProxyTarget(
                    name: group.name,
                    isGroup: true,
                    latency: nil,
                    region: MihomoAPIDecoder.regionCode(from: group.name)
                )
                liveGroupOrder.append(group.name)
            }
            for node in group.nodes where !node.isGroup && isSelectableTarget(node.name) {
                if let existing = liveNodesByName[node.name] {
                    if existing.latency == nil, let latency = node.latency {
                        liveNodesByName[node.name] = RoutingProxyTarget(
                            name: node.name,
                            isGroup: false,
                            latency: latency,
                            region: node.region
                        )
                    }
                } else {
                    liveNodesByName[node.name] = RoutingProxyTarget(
                        name: node.name,
                        isGroup: false,
                        latency: node.latency,
                        region: node.region
                    )
                    liveNodeOrder.append(node.name)
                }
            }
        }

        var emitted = Set<String>()
        var concreteNodes: [RoutingProxyTarget] = []
        var proxyGroups: [RoutingProxyTarget] = []

        // Preserve static YAML order first, enriching latencies from live Mihomo state.
        for item in staticTargets where !item.isGroup {
            guard emitted.insert(item.name).inserted else { continue }
            concreteNodes.append(liveNodesByName[item.name] ?? item)
        }
        // Include provider-supplied live nodes that are not listed statically in YAML.
        for name in liveNodeOrder where emitted.insert(name).inserted {
            if let target = liveNodesByName[name] {
                concreteNodes.append(target)
            }
        }

        for item in staticTargets where item.isGroup {
            guard emitted.insert(item.name).inserted else { continue }
            proxyGroups.append(liveGroupsByName[item.name] ?? item)
        }
        for name in liveGroupOrder where emitted.insert(name).inserted {
            if let target = liveGroupsByName[name] {
                proxyGroups.append(target)
            }
        }

        return concreteNodes + proxyGroups
    }

    private static func isSelectableTarget(_ name: String) -> Bool {
        !name.isEmpty && !excludedNames.contains(name.uppercased())
    }
}

enum RoutingInputError: Error, LocalizedError {
    case invalidDomain
    case missingProxyNode

    var errorDescription: String? {
        switch self {
        case .invalidDomain:
            "Enter a valid public URL or domain."
        case .missingProxyNode:
            "Select a proxy node or group for this routing rule."
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
                && MihomoYAMLValue.value("hidden", in: group)?.bool != true
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
        proxyName: String? = nil,
        profileID: ManagedProfile.ID
    ) throws {
        var registry = try loadRegistry()
        var values = registry[profileID.uuidString, default: []]
        values.removeAll { $0.domain == domain }
        values.append(RoutingOverride(domain: domain, policy: policy, proxyName: proxyName))
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
