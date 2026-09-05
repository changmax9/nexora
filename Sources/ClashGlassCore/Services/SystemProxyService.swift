import Foundation

public struct SystemProxySettings: Equatable, Sendable {
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
}

public struct SystemProxySnapshot: Equatable, Sendable {
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

    public init(executable: String = "/usr/sbin/networksetup", steps: [Step]) {
        self.executable = executable
        self.steps = steps
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
        ])
    }

    public static func restore(
        service: String,
        snapshot: SystemProxySnapshot
    ) -> SystemProxyCommand {
        SystemProxyCommand(steps: [
            .init(arguments: ["-setwebproxy", service, snapshot.web.host, "\(snapshot.web.port)"]),
            .init(arguments: ["-setwebproxystate", service, snapshot.web.enabled ? "on" : "off"]),
            .init(arguments: ["-setsecurewebproxy", service, snapshot.secureWeb.host, "\(snapshot.secureWeb.port)"]),
            .init(arguments: ["-setsecurewebproxystate", service, snapshot.secureWeb.enabled ? "on" : "off"]),
            .init(arguments: ["-setsocksfirewallproxy", service, snapshot.socks.host, "\(snapshot.socks.port)"]),
            .init(arguments: ["-setsocksfirewallproxystate", service, snapshot.socks.enabled ? "on" : "off"]),
        ])
    }
}

public struct SystemProxyService: Sendable {
    private let captureOverride: (@Sendable (String) throws -> SystemProxySnapshot)?
    private let applyOverride: (@Sendable (SystemProxyCommand) throws -> Void)?

    public init() {
        captureOverride = nil
        applyOverride = nil
    }

    init(
        capture: @escaping @Sendable (String) throws -> SystemProxySnapshot,
        apply: @escaping @Sendable (SystemProxyCommand) throws -> Void
    ) {
        captureOverride = capture
        applyOverride = apply
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
        for step in command.steps {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = step.arguments
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw SystemProxyError.commandFailed(step.arguments)
            }
        }
    }

    private func output(arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments):
            "networksetup failed: \(arguments.joined(separator: " "))"
        case .invalidOutput:
            "Could not read the current macOS proxy settings."
        }
    }
}
