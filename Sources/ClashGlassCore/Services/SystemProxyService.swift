import Foundation

public struct SystemProxySettings: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let host: String
    public let port: Int

    public init(enabled: Bool, host: String, port: Int) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    public static func parse(networksetupOutput: String) throws -> SystemProxySettings {
        let values = Dictionary(uniqueKeysWithValues: networksetupOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (String, String)? in
                guard let separator = line.firstIndex(of: ":") else {
                    return nil
                }
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                return (key, value)
            })
        guard let enabled = values["Enabled"],
              let host = values["Server"],
              let portText = values["Port"],
              let port = Int(portText) else {
            throw SystemProxyError.invalidOutput(networksetupOutput)
        }
        return SystemProxySettings(
            enabled: enabled.caseInsensitiveCompare("Yes") == .orderedSame,
            host: host,
            port: port
        )
    }

    private var normalizedHost: String {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) ? "loopback" : host
    }

    func removingProxy(host: String, port: Int) -> SystemProxySettings {
        let endpoint = SystemProxySettings(enabled: true, host: host, port: port)
        guard normalizedHost == endpoint.normalizedHost, self.port == port else { return self }
        return SystemProxySettings(enabled: false, host: self.host, port: self.port)
    }

    func hasSameEffectiveSettings(as other: SystemProxySettings) -> Bool {
        enabled == other.enabled
            && (!enabled || (normalizedHost == other.normalizedHost && port == other.port))
    }
}

public struct SystemProxySnapshot: Codable, Equatable, Sendable {
    public let web: SystemProxySettings
    public let secureWeb: SystemProxySettings
    public let socks: SystemProxySettings

    public init(
        web: SystemProxySettings,
        secureWeb: SystemProxySettings,
        socks: SystemProxySettings
    ) {
        self.web = web
        self.secureWeb = secureWeb
        self.socks = socks
    }

    /// A previous crash may have left our own listener enabled. Restoring it
    /// before stopping that listener would leave every proxied app offline.
    func removingProxy(host: String, httpPort: Int, socksPort: Int) -> SystemProxySnapshot {
        SystemProxySnapshot(
            web: web.removingProxy(host: host, port: httpPort),
            secureWeb: secureWeb.removingProxy(host: host, port: httpPort),
            socks: socks.removingProxy(host: host, port: socksPort)
        )
    }

    func hasSameEffectiveSettings(as other: SystemProxySnapshot) -> Bool {
        web.hasSameEffectiveSettings(as: other.web)
            && secureWeb.hasSameEffectiveSettings(as: other.secureWeb)
            && socks.hasSameEffectiveSettings(as: other.socks)
    }

    static func enabled(host: String, httpPort: Int, socksPort: Int) -> SystemProxySnapshot {
        .init(
            web: .init(enabled: true, host: host, port: httpPort),
            secureWeb: .init(enabled: true, host: host, port: httpPort),
            socks: .init(enabled: true, host: host, port: socksPort)
        )
    }

    func restorationTarget(current: SystemProxySnapshot, owned: SystemProxySnapshot) -> SystemProxySnapshot {
        func target(_ original: SystemProxySettings, _ actual: SystemProxySettings, _ managed: SystemProxySettings) -> SystemProxySettings {
            actual.hasSameEffectiveSettings(as: managed) || actual.hasSameEffectiveSettings(as: original) ? original : actual
        }
        return .init(
            web: target(web, current.web, owned.web),
            secureWeb: target(secureWeb, current.secureWeb, owned.secureWeb),
            socks: target(socks, current.socks, owned.socks)
        )
    }
}

public struct SystemProxyCommand: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let arguments: [String]

        public init(arguments: [String]) {
            self.arguments = arguments
        }
    }

    public let executable: String
    public let steps: [Step]
    public let continuesAfterFailure: Bool

    public init(
        executable: String = "/usr/sbin/networksetup",
        steps: [Step],
        continuesAfterFailure: Bool = false
    ) {
        self.executable = executable
        self.steps = steps
        self.continuesAfterFailure = continuesAfterFailure
    }

    public static func enable(service: String, host: String, httpPort: Int, socksPort: Int) -> SystemProxyCommand {
        SystemProxyCommand(steps: [
            .init(arguments: ["-setwebproxy", service, host, "\(httpPort)"]),
            .init(arguments: ["-setsecurewebproxy", service, host, "\(httpPort)"]),
            .init(arguments: ["-setsocksfirewallproxy", service, host, "\(socksPort)"]),
        ])
    }

    public static func disable(service: String) -> SystemProxyCommand {
        SystemProxyCommand(steps: [
            .init(arguments: ["-setwebproxystate", service, "off"]),
            .init(arguments: ["-setsecurewebproxystate", service, "off"]),
            .init(arguments: ["-setsocksfirewallproxystate", service, "off"]),
        ], continuesAfterFailure: true)
    }

    public static func restore(
        service: String,
        snapshot: SystemProxySnapshot,
        current: SystemProxySnapshot? = nil,
        ownedSnapshot: SystemProxySnapshot? = nil
    ) -> SystemProxyCommand {
        let proxies = [
            ("-setwebproxy", "-setwebproxystate", snapshot.web, current?.web, ownedSnapshot?.web),
            ("-setsecurewebproxy", "-setsecurewebproxystate", snapshot.secureWeb, current?.secureWeb, ownedSnapshot?.secureWeb),
            ("-setsocksfirewallproxy", "-setsocksfirewallproxystate", snapshot.socks, current?.socks, ownedSnapshot?.socks),
        ]
        var steps: [Step] = []
        for (endpointArgument, stateArgument, settings, actual, owned) in proxies {
            if let actual, let owned,
               !actual.hasSameEffectiveSettings(as: owned),
               !actual.hasSameEffectiveSettings(as: settings) { continue }
            // Setting an endpoint also enables it. A failed following "off"
            // would leave a formerly inactive server handling browser traffic.
            if settings.enabled {
                steps.append(.init(arguments: [endpointArgument, service, settings.host, "\(settings.port)"]))
            }
            steps.append(.init(arguments: [stateArgument, service, settings.enabled ? "on" : "off"]))
        }
        return SystemProxyCommand(steps: steps, continuesAfterFailure: true)
    }
}

public struct SystemProxyService: Sendable {
    private let captureOverride: (@Sendable (String) throws -> SystemProxySnapshot)?
    private let applyOverride: (@Sendable (SystemProxyCommand) throws -> Void)?
    private let runOverride: (@Sendable (String, [String]) throws -> String)?

    public init() {
        captureOverride = nil
        applyOverride = nil
        runOverride = nil
    }

    init(
        capture: @escaping @Sendable (String) throws -> SystemProxySnapshot,
        apply: @escaping @Sendable (SystemProxyCommand) throws -> Void
    ) {
        captureOverride = capture
        applyOverride = apply
        runOverride = nil
    }

    init(run: @escaping @Sendable (String, [String]) throws -> String) {
        captureOverride = nil
        applyOverride = nil
        runOverride = run
    }

    public func capture(service: String) throws -> SystemProxySnapshot {
        if let captureOverride { return try captureOverride(service) }
        return SystemProxySnapshot(
            web: try SystemProxySettings.parse(
                networksetupOutput: output(arguments: ["-getwebproxy", service])
            ),
            secureWeb: try SystemProxySettings.parse(
                networksetupOutput: output(arguments: ["-getsecurewebproxy", service])
            ),
            socks: try SystemProxySettings.parse(
                networksetupOutput: output(arguments: ["-getsocksfirewallproxy", service])
            )
        )
    }

    public func apply(_ command: SystemProxyCommand) throws {
        if let applyOverride { return try applyOverride(command) }
        var firstFailure: (any Error)?
        for step in command.steps {
            do {
                _ = try output(executable: command.executable, arguments: step.arguments)
            } catch {
                guard command.continuesAfterFailure else { throw error }
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    public func restore(service: String, snapshot: SystemProxySnapshot, ownedSnapshot: SystemProxySnapshot? = nil) throws {
        let current = try ownedSnapshot.map { _ in try capture(service: service) }
        let command = SystemProxyCommand.restore(service: service, snapshot: snapshot, current: current, ownedSnapshot: ownedSnapshot)
        guard !command.steps.isEmpty else { return }
        let target: SystemProxySnapshot
        if let current, let ownedSnapshot {
            target = snapshot.restorationTarget(current: current, owned: ownedSnapshot)
        } else {
            target = snapshot
        }
        try apply(command)
        guard try capture(service: service).hasSameEffectiveSettings(as: target) else {
            throw SystemProxyError.restorationNotVerified(service)
        }
    }

    private func output(executable: String = "/usr/sbin/networksetup", arguments: [String]) throws -> String {
        if let runOverride { return try runOverride(executable, arguments) }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw SystemProxyError.commandFailed(arguments)
        }
        return output
    }
}

public enum SystemProxyError: Error, Equatable, LocalizedError {
    case commandFailed([String])
    case invalidOutput(String)
    case restorationNotVerified(String)
    case ownedByAnotherInstance

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments):
            "networksetup failed: \(arguments.joined(separator: " "))"
        case .invalidOutput:
            "Could not read the current macOS proxy settings."
        case let .restorationNotVerified(service):
            "macOS proxy settings for \(service) were not restored. Retry restoring the system proxy."
        case .ownedByAnotherInstance:
            "Another Nexora instance owns the active connection. Use that instance or quit it before connecting here."
        }
    }
}
