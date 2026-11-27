import Darwin
import Foundation
import NexoraTUNSupport
import Yams

public struct PreparedRuntimeConfiguration: Equatable, Sendable {
    public let configURL: URL
    public let runtimeDirectoryURL: URL
    public let mixedPort: Int
    public let controllerURL: URL
    public let controllerSecret: String?
    public let dnsListenPort: Int?
}

public struct RuntimePortAllocator: Sendable {
    private let isTCPPortAvailable: @Sendable (String, Int) -> Bool
    private let isUDPPortAvailable: @Sendable (String, Int) -> Bool

    public init() {
        isTCPPortAvailable = Self.canBindTCP
        isUDPPortAvailable = Self.canBindUDP
    }

    public init(
        isTCPPortAvailable: @escaping @Sendable (String, Int) -> Bool,
        isUDPPortAvailable: @escaping @Sendable (String, Int) -> Bool
    ) {
        self.isTCPPortAvailable = isTCPPortAvailable
        self.isUDPPortAvailable = isUDPPortAvailable
    }

    public func availableTCPPort(host: String, preferredPort: Int, excluding: Set<Int> = []) throws -> Int {
        try availablePort(host: host, preferredPort: preferredPort, excluding: excluding) { host, port in
            isTCPPortAvailable(host, port)
        }
    }

    public func availableTCPAndUDPPort(host: String, preferredPort: Int, excluding: Set<Int> = []) throws -> Int {
        try availablePort(host: host, preferredPort: preferredPort, excluding: excluding) { host, port in
            isTCPPortAvailable(host, port) && isUDPPortAvailable(host, port)
        }
    }

    private func availablePort(
        host: String,
        preferredPort: Int,
        excluding: Set<Int>,
        isAvailable: (String, Int) -> Bool
    ) throws -> Int {
        guard (1...65_535).contains(preferredPort) else {
            throw RuntimeConfigurationError.noAvailablePort(preferredPort)
        }
        for port in preferredPort...min(preferredPort + 200, 65_535)
            where !excluding.contains(port) && isAvailable(host, port) {
            return port
        }
        throw RuntimeConfigurationError.noAvailablePort(preferredPort)
    }

    private static func canBindTCP(host: String, port: Int) -> Bool {
        canBind(host: host, port: port, socketType: SOCK_STREAM)
    }

    private static func canBindUDP(host: String, port: Int) -> Bool {
        canBind(host: host, port: port, socketType: SOCK_DGRAM)
    }

    private static func canBind(host: String, port: Int, socketType: Int32) -> Bool {
        let descriptor = socket(AF_INET, socketType, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        let bindHost = host == "localhost" ? "127.0.0.1" : host
        guard inet_pton(AF_INET, bindHost, &address.sin_addr) == 1 else {
            return false
        }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

public struct RuntimeConfigurationPreparer: Sendable {
    public let geoDataSourceURL: URL?
    public let portAllocator: RuntimePortAllocator

    public init(
        geoDataSourceURL: URL? = Self.defaultGeoDataSourceURL(),
        portAllocator: RuntimePortAllocator = RuntimePortAllocator()
    ) {
        self.geoDataSourceURL = geoDataSourceURL
        self.portAllocator = portAllocator
    }

    public func prepare(
        sourceURL: URL,
        runtimeDirectoryURL: URL,
        routingOverrides: [RoutingOverride] = [],
        privilegedTUN: Bool = false
    ) throws -> PreparedRuntimeConfiguration {
        let sourceYAML = try String(contentsOf: sourceURL, encoding: .utf8)
        let settings = try MihomoConfigurationInspector.inspect(yaml: sourceYAML)
        let vpnRuleTarget: String?
        if routingOverrides.contains(where: { $0.policy == .vpn }) {
            guard let target = RoutingVPNTargetResolver.target(from: sourceYAML) else {
                throw RuntimeConfigurationError.missingVPNPolicyGroup
            }
            vpnRuleTarget = target
        } else {
            vpnRuleTarget = nil
        }
        let mixedPort = try portAllocator.availableTCPPort(
            host: "127.0.0.1",
            preferredPort: settings.httpPort
        )
        let controllerPort = try portAllocator.availableTCPPort(
            host: "127.0.0.1",
            preferredPort: settings.controllerPort,
            excluding: [mixedPort]
        )
        let dnsListenPort: Int?
        if let preferredDNSPort = settings.dnsListenPort {
            dnsListenPort = try portAllocator.availableTCPAndUDPPort(
                host: "127.0.0.1",
                preferredPort: preferredDNSPort,
                excluding: [mixedPort, controllerPort]
            )
        } else {
            dnsListenPort = nil
        }

        var runtimeYAML = try rewrite(
            yaml: sourceYAML,
            mixedPort: mixedPort,
            controllerPort: controllerPort,
            dnsListenPort: dnsListenPort,
            routingOverrides: routingOverrides,
            vpnRuleTarget: vpnRuleTarget
        )
        let controllerSecret = privilegedTUN ? UUID().uuidString + UUID().uuidString : settings.secret
        if privilegedTUN, let controllerSecret {
            runtimeYAML = try TUNConfiguration.normalized(yaml: runtimeYAML, secret: controllerSecret)
        }
        try FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: true
        )
        let configURL = runtimeDirectoryURL.appendingPathComponent("config.yaml")
        try runtimeYAML.write(to: configURL, atomically: true, encoding: .utf8)
        try copyGeoData(to: runtimeDirectoryURL)

        return PreparedRuntimeConfiguration(
            configURL: configURL,
            runtimeDirectoryURL: runtimeDirectoryURL,
            mixedPort: mixedPort,
            controllerURL: URL(string: "http://127.0.0.1:\(controllerPort)")!,
            controllerSecret: controllerSecret,
            dnsListenPort: dnsListenPort
        )
    }

    public static func defaultGeoDataSourceURL() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("GeoData", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("runtime-assets", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    /// The imported file remains the source of truth. Validate a compatible
    /// temporary copy only when an old DNS policy needs the same runtime fix.
    func validationConfiguration(yaml: String) throws -> String? {
        guard var configuration = try Yams.compose(yaml: yaml), configuration.mapping != nil else {
            throw MihomoConfigurationInspectionError.invalidMapping
        }
        guard normalizeLegacyDNSPolicies(in: &configuration) else { return nil }
        var mapping = configuration.mapping!
        mapping.style = .block
        return try Yams.serialize(node: .mapping(mapping), allowUnicode: true)
    }

    private func rewrite(
        yaml: String,
        mixedPort: Int,
        controllerPort: Int,
        dnsListenPort: Int?,
        routingOverrides: [RoutingOverride],
        vpnRuleTarget: String?
    ) throws -> String {
        guard var configuration = try Yams.compose(yaml: yaml), configuration.mapping != nil else {
            throw MihomoConfigurationInspectionError.invalidMapping
        }
        configuration["mixed-port"] = Node(String(mixedPort), Tag(.int))
        // Both macOS proxy protocols use the managed mixed listener. Leaving
        // imported dedicated listeners enabled can bind the same port twice.
        for key in ["port", "socks-port"] where MihomoYAMLValue.value(key, in: configuration) != nil {
            configuration[key] = Node("0", Tag(.int))
        }
        configuration["external-controller"] = Node("127.0.0.1:\(controllerPort)", Tag(.str), .singleQuoted)
        configuration["unified-delay"] = Node("true", Tag(.bool))
        configuration["tcp-concurrent"] = Node("true", Tag(.bool))
        if let dnsListenPort, var dns = MihomoYAMLValue.value("dns", in: configuration), dns.mapping != nil {
            dns["listen"] = Node("127.0.0.1:\(dnsListenPort)", Tag(.str), .singleQuoted)
            configuration["dns"] = dns
        }

        _ = normalizeLegacyDNSPolicies(in: &configuration)

        // YAML's block and flow collections have the same meaning. Build the rule
        // list from parsed nodes so adding a rule never introduces a second key or
        // mixes an unindented list with indented list entries.
        let existingRules = MihomoYAMLValue.value("rules", in: configuration)
        let ruleIndentation: String
        if let mark = existingRules?.sequence?.mark,
           let line = yaml.split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst(mark.line - 1).first,
           line.unicodeScalars.dropFirst(mark.column - 1).first == "-" {
            ruleIndentation = String(repeating: " ", count: max(0, mark.column - 1))
        } else {
            ruleIndentation = "  "
        }
        if !routingOverrides.isEmpty {
            guard existingRules == nil || existingRules?.null != nil || existingRules?.sequence != nil else {
                throw RuntimeConfigurationError.invalidRules
            }
            let generated = routingOverrides.sorted { $0.domain < $1.domain }.compactMap { rule -> Node? in
                if rule.policy == .vpn, vpnRuleTarget == nil { return nil }
                let target = rule.policy.ruleTarget(vpnTarget: vpnRuleTarget ?? "")
                return Node("DOMAIN-SUFFIX,\(rule.domain),\(target)", Tag(.str), .singleQuoted)
            }
            configuration["rules"] = Node(generated + (existingRules?.array() ?? []), .implicit, .block)
        }

        // Emit one complete YAML document. A literal scalar with a keep-chomping
        // indicator can make libYAML emit an explicit document end; concatenating
        // separately emitted top-level entries would then create invalid YAML.
        var mapping = configuration.mapping!
        mapping.style = .block
        var output = try Yams.serialize(node: .mapping(mapping), allowUnicode: true)
        if !routingOverrides.isEmpty,
           let emitted = try Yams.compose(yaml: output),
           let ruleKey = emitted.mapping?.first(where: { $0.key.string == "rules" })?.key,
           let mark = ruleKey.mark {
            // Only add a comment after the parsed key. Rule values and all scalar
            // escaping stay entirely under the YAML emitter's control.
            var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            lines.insert("\(ruleIndentation)# Nexora routing overrides", at: mark.line)
            output = lines.joined(separator: "\n")
        }
        return output
    }

    private func normalizeLegacyDNSPolicies(in configuration: inout Node) -> Bool {
        guard var dns = MihomoYAMLValue.value("dns", in: configuration), dns.mapping != nil else { return false }
        var changedDNS = false
        for field in ["nameserver-policy", "proxy-server-nameserver-policy"] {
            guard let policy = MihomoYAMLValue.value(field, in: dns), policy.mapping != nil else { continue }
            var changedPolicy = false
            let compatible = removingLegacyLiteralDNSPolicies(policy, changed: &changedPolicy)
            if changedPolicy {
                dns[field] = compatible
                changedDNS = true
            }
        }
        if changedDNS { configuration["dns"] = dns }
        return changedDNS
    }

    private func removingLegacyLiteralDNSPolicies(_ node: Node, changed: inout Bool) -> Node {
        if let sequence = node.sequence {
            let values = sequence.map { removingLegacyLiteralDNSPolicies($0, changed: &changed) }
            return Node(values, sequence.tag, sequence.style)
        }
        guard let mapping = node.mapping else { return node }
        var occupiedKeys = Set(mapping.compactMap { $0.key.string })
        var pairs: [(Node, Node)] = []
        for pair in mapping {
            if pair.key.tag == Tag(.merge) {
                pairs.append((pair.key, removingLegacyLiteralDNSPolicies(pair.value, changed: &changed)))
                continue
            }
            guard let key = pair.key.string,
                  !key.lowercased().hasPrefix("geosite:"),
                  !key.lowercased().hasPrefix("rule-set:") else {
                pairs.append((pair.key, pair.value))
                continue
            }
            let domains = key.components(separatedBy: ",")
            let retained = domains.filter { domain in
                !domain.components(separatedBy: ".").enumerated().contains { index, label in
                    label.contains("+") && (index > 0 || label != "+")
                }
            }
            guard retained.count != domains.count else {
                pairs.append((pair.key, pair.value))
                continue
            }
            // The old DNS DomainTrie treated a misplaced '+' as a literal label,
            // so it never matched ordinary hostnames. Omit only those ineffective
            // domains in the private runtime; changing '+' to '*' would widen the
            // policy. A bare '+' had broad matching behavior and is left untouched.
            // https://github.com/MetaCubeX/mihomo/blob/v1.19.27/component/trie/domain.go
            changed = true
            guard let first = retained.first else { continue }
            var compatibleKey = retained.joined(separator: ",")
            // Preserve ordered policy entries without creating duplicate YAML keys.
            // Repeating a retained domain has no effect on the trie insertion.
            while occupiedKeys.contains(compatibleKey) {
                compatibleKey += "," + first
            }
            occupiedKeys.insert(compatibleKey)
            pairs.append((Node(compatibleKey, Tag(.str), .singleQuoted), pair.value))
        }
        return Node(pairs, mapping.tag, mapping.style)
    }

    private func copyGeoData(to runtimeDirectoryURL: URL) throws {
        guard let geoDataSourceURL else {
            throw RuntimeConfigurationError.geoDataMissing
        }

        let files: [(destination: String, candidates: [String])] = [
            ("geoip.dat", ["geoip.dat", "GEOIP.dat"]),
            ("geosite.dat", ["geosite.dat", "GEOSITE.dat"]),
            ("geoip.metadb", ["geoip.metadb", "GEOIP.metadb"]),
            ("ASN.mmdb", ["ASN.mmdb"]),
        ]

        var copiedRequiredFiles = Set<String>()
        for file in files {
            guard let source = file.candidates
                .map({ geoDataSourceURL.appendingPathComponent($0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                continue
            }
            let destination = runtimeDirectoryURL.appendingPathComponent(file.destination)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            copiedRequiredFiles.insert(file.destination)
        }

        guard copiedRequiredFiles.contains("geoip.dat"),
              copiedRequiredFiles.contains("geosite.dat") else {
            throw RuntimeConfigurationError.geoDataMissing
        }
    }
}

public enum RuntimeConfigurationError: Error, LocalizedError, Equatable {
    case noAvailablePort(Int)
    case geoDataMissing
    case missingVPNPolicyGroup
    case invalidRules

    public var errorDescription: String? {
        switch self {
        case let .noAvailablePort(preferredPort):
            "No free local port was found near \(preferredPort)."
        case .geoDataMissing:
            "Nexora is missing the GeoIP and GeoSite runtime data."
        case .missingVPNPolicyGroup:
            "This profile has no selectable proxy group for VPN routing rules."
        case .invalidRules:
            "The profile's 'rules' field must be a YAML list."
        }
    }
}
