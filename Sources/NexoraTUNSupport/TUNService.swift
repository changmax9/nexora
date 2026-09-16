import Foundation
import Security
import Yams

public enum TUNServiceIdentity {
    public static let name = "com.maxchang.Nexora.TUNHelper"
    public static let plistName = name + ".plist"

    public static func requirement(identifier: String) throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else {
            throw TUNServiceError("TUN requires Nexora and its helper to be signed with an Apple development or distribution certificate.")
        }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

public struct TUNServiceError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

@objc public protocol TUNHelperProtocol {
    func start(configuration: Data, reply: @escaping @Sendable (String?) -> Void)
    func stop(reply: @escaping @Sendable () -> Void)
    func status(reply: @escaping @Sendable (Bool, String) -> Void)
}

public enum TUNConfiguration {
    public static let maximumSize = 8 * 1024 * 1024

    /// Converts the selected profile to a private helper configuration. The helper
    /// repeats this normalization at the privilege boundary, never accepting paths
    /// or executable names supplied by the caller.
    public static func normalized(yaml: String, secret: String) throws -> String {
        guard yaml.utf8.count <= maximumSize,
              secret.count >= 32,
              var config = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw TUNServiceError("The TUN profile is invalid or too large.")
        }
        guard let controller = config["external-controller"] as? String,
              controller.hasPrefix("127.0.0.1:"),
              let port = Int(controller.dropFirst("127.0.0.1:".count)), (1024...65535).contains(port) else {
            throw TUNServiceError("TUN requires a private loopback controller on an unprivileged port.")
        }
        config["secret"] = secret
        try validateCertificateReferences(config)
        config["allow-lan"] = false
        config["bind-address"] = "127.0.0.1"
        for key in ["external-controller-unix", "external-controller-pipe", "external-controller-tls", "external-ui", "external-ui-url", "external-ui-name", "tls", "listeners"] {
            config.removeValue(forKey: key)
        }
        // Files downloaded by providers stay inside the helper's private directory.
        for group in ["proxy-providers", "rule-providers"] {
            if var providers = config[group] as? [String: Any] {
                for (name, value) in providers {
                    guard var provider = value as? [String: Any] else { continue }
                    if let path = provider["path"] as? String {
                        guard !path.hasPrefix("/"), !path.hasPrefix("~"),
                              !path.split(separator: "/").contains(".."),
                              !path.contains("\\") else {
                            throw TUNServiceError("TUN provider '\(name)' uses an external file path. Import a profile with relative provider paths.")
                        }
                    }
                    if provider["type"] as? String == "file" {
                        throw TUNServiceError("TUN cannot copy external file provider '\(name)'. Use an inline or HTTP provider.")
                    }
                    provider["path"] = "providers/\(UUID().uuidString).yaml"
                    providers[name] = provider
                }
                config[group] = providers
            }
        }
        config["tun"] = [
            "enable": true, "stack": "gvisor", "auto-route": true,
            "auto-detect-interface": true, "dns-hijack": ["any:53", "tcp://any:53"]
        ] as [String: Any]
        var dns = config["dns"] as? [String: Any] ?? [:]
        dns["enable"] = true
        if dns["nameserver"] == nil { dns["nameserver"] = ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"] }
        config["dns"] = dns
        return try Yams.dump(object: config)
    }

    public static func validateAtBoundary(_ data: Data) throws -> Data {
        guard data.count <= maximumSize, let yaml = String(data: data, encoding: .utf8),
              let config = try Yams.load(yaml: yaml) as? [String: Any],
              let secret = config["secret"] as? String else {
            throw TUNServiceError("Missing authenticated TUN configuration.")
        }
        return Data(try normalized(yaml: yaml, secret: secret).utf8)
    }

    private static func validateCertificateReferences(_ value: Any, depth: Int = 0) throws {
        guard depth < 64 else { throw TUNServiceError("TUN configuration nesting is too deep.") }
        if let object = value as? [String: Any] {
            for (key, child) in object {
                if ["certificate", "private-key", "client-cert", "client-key", "ca"].contains(key),
                   let path = child as? String, !path.isEmpty,
                   !path.contains("-----BEGIN ") {
                    throw TUNServiceError("TUN requires inline PEM certificates; external certificate files are not read with administrator privileges.")
                }
                try validateCertificateReferences(child, depth: depth + 1)
            }
        } else if let values = value as? [Any] {
            for child in values { try validateCertificateReferences(child, depth: depth + 1) }
        }
    }
}
