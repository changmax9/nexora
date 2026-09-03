import Darwin
import Foundation

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

    public func availableTCPPort(host: String, preferredPort: Int) throws -> Int {
        try availablePort(host: host, preferredPort: preferredPort) { host, port in
            isTCPPortAvailable(host, port)
        }
    }

    public func availableTCPAndUDPPort(host: String, preferredPort: Int) throws -> Int {
        try availablePort(host: host, preferredPort: preferredPort) { host, port in
            isTCPPortAvailable(host, port) && isUDPPortAvailable(host, port)
        }
    }

    private func availablePort(
        host: String,
        preferredPort: Int,
        isAvailable: (String, Int) -> Bool
    ) throws -> Int {
        for port in preferredPort...min(preferredPort + 200, 65_535) where isAvailable(host, port) {
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
        routingOverrides: [RoutingOverride] = []
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
            preferredPort: settings.controllerPort
        )
        let dnsListenPort: Int?
        if let preferredDNSPort = settings.dnsListenPort {
            dnsListenPort = try portAllocator.availableTCPAndUDPPort(
                host: settings.dnsListenHost ?? "127.0.0.1",
                preferredPort: preferredDNSPort
            )
        } else {
            dnsListenPort = nil
        }

        let runtimeYAML = rewrite(
            yaml: sourceYAML,
            mixedPort: mixedPort,
            controllerPort: controllerPort,
            dnsListenPort: dnsListenPort,
            routingOverrides: routingOverrides,
            vpnRuleTarget: vpnRuleTarget
        )
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
            controllerSecret: settings.secret,
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

    private func rewrite(
        yaml: String,
        mixedPort: Int,
        controllerPort: Int,
        dnsListenPort: Int?,
        routingOverrides: [RoutingOverride],
        vpnRuleTarget: String?
    ) -> String {
        var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var foundMixedPort = false
        var foundController = false
        var foundUnifiedDelay = false
        var foundTCPConcurrent = false
        var insideDNS = false

        for index in lines.indices {
            let line = lines[index]
            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if indentation == 0 {
                insideDNS = trimmed.hasPrefix("dns:")
                if trimmed.hasPrefix("mixed-port:") {
                    lines[index] = "mixed-port: \(mixedPort)"
                    foundMixedPort = true
                } else if trimmed.hasPrefix("external-controller:") {
                    lines[index] = "external-controller: '127.0.0.1:\(controllerPort)'"
                    foundController = true
                } else if trimmed.hasPrefix("unified-delay:") {
                    lines[index] = "unified-delay: true"
                    foundUnifiedDelay = true
                } else if trimmed.hasPrefix("tcp-concurrent:") {
                    lines[index] = "tcp-concurrent: true"
                    foundTCPConcurrent = true
                }
            } else if insideDNS,
                      let dnsListenPort,
                      trimmed.hasPrefix("listen:") {
                let prefix = String(line.prefix(indentation))
                lines[index] = "\(prefix)listen: '127.0.0.1:\(dnsListenPort)'"
            }
        }

        if !foundMixedPort {
            lines.insert("mixed-port: \(mixedPort)", at: 0)
        }
        if !foundController {
            lines.insert("external-controller: '127.0.0.1:\(controllerPort)'", at: min(1, lines.count))
        }
        var performanceSettings: [String] = []
        if !foundUnifiedDelay {
            performanceSettings.append("unified-delay: true")
        }
        if !foundTCPConcurrent {
            performanceSettings.append("tcp-concurrent: true")
        }
        lines.insert(contentsOf: performanceSettings, at: 0)
        insertRoutingOverrides(
            routingOverrides,
            vpnRuleTarget: vpnRuleTarget,
            into: &lines
        )
        return lines.joined(separator: "\n")
    }

    private func insertRoutingOverrides(
        _ overrides: [RoutingOverride],
        vpnRuleTarget: String?,
        into lines: inout [String]
    ) {
        guard !overrides.isEmpty else {
            return
        }
        if let rulesIndex = lines.firstIndex(where: { line in
            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            return indentation == 0
                && line.trimmingCharacters(in: .whitespaces) == "rules:"
        }) {
            var childIndent = "  "
            if rulesIndex + 1 < lines.count {
                for line in lines[(rulesIndex + 1)...] {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else {
                        continue
                    }
                    let indentation = line.prefix { $0 == " " || $0 == "\t" }
                    if indentation.isEmpty {
                        break
                    }
                    childIndent = String(indentation)
                    break
                }
            }
            let generatedLines = generatedRoutingLines(
                overrides,
                vpnRuleTarget: vpnRuleTarget,
                indentation: childIndent
            )
            lines.insert(contentsOf: generatedLines, at: rulesIndex + 1)
        } else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("rules:")
            lines.append(contentsOf: generatedRoutingLines(
                overrides,
                vpnRuleTarget: vpnRuleTarget,
                indentation: "  "
            ))
        }
    }

    private func generatedRoutingLines(
        _ overrides: [RoutingOverride],
        vpnRuleTarget: String?,
        indentation: String
    ) -> [String] {
        [
            "\(indentation)# Nexora routing overrides",
        ] + overrides
            .sorted { $0.domain < $1.domain }
            .compactMap { routingOverride in
                let target: String
                switch routingOverride.policy {
                case .vpn:
                    guard let vpnRuleTarget else {
                        return nil
                    }
                    target = routingOverride.policy.ruleTarget(vpnTarget: vpnRuleTarget)
                case .direct:
                    target = routingOverride.policy.ruleTarget(vpnTarget: "")
                }
                return "\(indentation)- 'DOMAIN-SUFFIX,\(routingOverride.domain),\(target)'"
            }
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

    public var errorDescription: String? {
        switch self {
        case let .noAvailablePort(preferredPort):
            "No free local port was found near \(preferredPort)."
        case .geoDataMissing:
            "Nexora is missing the GeoIP and GeoSite runtime data."
        case .missingVPNPolicyGroup:
            "This profile has no selectable proxy group for VPN routing rules."
        }
    }
}
