import Foundation
import Yams

public struct MihomoConfigurationSettings: Equatable, Sendable {
    public let httpPort: Int
    public let socksPort: Int
    public let controllerHost: String
    public let controllerPort: Int
    public let secret: String?
    public let mode: OutboundMode
    public let tunEnabled: Bool
    public let dnsListenHost: String?
    public let dnsListenPort: Int?
}

public enum MihomoConfigurationInspector {
    public static func inspect(url: URL) throws -> MihomoConfigurationSettings {
        try inspect(yaml: String(contentsOf: url, encoding: .utf8))
    }

    public static func inspect(yaml: String) throws -> MihomoConfigurationSettings {
        guard let configuration = try Yams.compose(yaml: yaml), configuration.mapping != nil else {
            throw MihomoConfigurationInspectionError.invalidMapping
        }
        func value(_ key: String) -> Node? { MihomoYAMLValue.value(key, in: configuration) }
        let mixedPort = try port(value("mixed-port"), field: "mixed-port") ?? 7890
        let controller = try endpoint(
            value("external-controller")?.string ?? "127.0.0.1:9090",
            field: "external-controller",
            defaultPort: 9090
        )
        let secret = value("secret")?.string
        let dnsListen: (host: String, port: Int?)?
        if let listen = MihomoYAMLValue.value("listen", in: value("dns"))?.string {
            dnsListen = try endpoint(listen, field: "dns.listen", defaultPort: nil)
        } else {
            dnsListen = nil
        }

        return MihomoConfigurationSettings(
            httpPort: try port(value("port"), field: "port") ?? mixedPort,
            socksPort: try port(value("socks-port"), field: "socks-port") ?? mixedPort,
            controllerHost: controller.host,
            controllerPort: controller.port ?? 9090,
            secret: secret?.isEmpty == false ? secret : nil,
            mode: OutboundMode(rawValue: value("mode")?.string?.lowercased() ?? "") ?? .rule,
            tunEnabled: MihomoYAMLValue.value("enable", in: value("tun"))?.bool ?? false,
            dnsListenHost: dnsListen?.host,
            dnsListenPort: dnsListen?.port
        )
    }

    private static func port(_ node: Node?, field: String) throws -> Int? {
        guard let node, node.null == nil else { return nil }
        guard let value = node.int, (0...65_535).contains(value) else {
            throw MihomoConfigurationInspectionError.invalidPort(field)
        }
        // A disabled listener is assigned a private port when materializing the runtime.
        return value == 0 ? nil : value
    }

    private static func endpoint(
        _ value: String,
        field: String,
        defaultPort: Int?
    ) throws -> (host: String, port: Int?) {
        let address = value.isEmpty ? "127.0.0.1" : value
        let authority = address.hasPrefix(":") && !address.hasPrefix("::")
            ? "127.0.0.1\(address)" : address
        guard let components = URLComponents(string: "http://\(authority)"),
              var host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.path.isEmpty, components.query == nil, components.fragment == nil else {
            throw MihomoConfigurationInspectionError.invalidEndpoint(field)
        }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        let port = components.port ?? defaultPort
        if let port, !(1...65_535).contains(port) {
            throw MihomoConfigurationInspectionError.invalidPort(field)
        }
        return (host, port)
    }
}

public enum MihomoConfigurationInspectionError: Error, LocalizedError, Equatable {
    case invalidMapping
    case invalidPort(String)
    case invalidEndpoint(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMapping:
            "The Mihomo configuration must be a YAML mapping."
        case let .invalidPort(field):
            "The '\(field)' port must be between 0 and 65535."
        case let .invalidEndpoint(field):
            "The '\(field)' address must contain a valid host and port."
        }
    }
}

/// Node subscripts intentionally expose only explicit keys. Resolve YAML merge
/// defaults when inspecting settings without flattening or changing stored nodes.
enum MihomoYAMLValue {
    static func value(_ key: String, in node: Node?, depth: Int = 0) -> Node? {
        guard depth < 64, let mapping = node?.mapping else { return nil }
        if let explicit = mapping[key] { return explicit }
        for pair in mapping.reversed() where pair.key.tag == Tag(.merge) {
            if pair.value.mapping != nil {
                if let inherited = value(key, in: pair.value, depth: depth + 1) { return inherited }
            } else if let sources = pair.value.sequence {
                // Earlier mappings in a YAML merge list take precedence.
                for source in sources {
                    if let inherited = value(key, in: source, depth: depth + 1) { return inherited }
                }
            }
        }
        return nil
    }
}
