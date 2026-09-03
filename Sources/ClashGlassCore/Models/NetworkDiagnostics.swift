import Darwin
import Foundation

public enum NetworkDiagnosticSeverity: String, Equatable, Sendable {
    case healthy
    case warning
    case critical

    var symbol: String {
        switch self {
        case .healthy: "checkmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}

public struct NetworkDiagnosticSnapshot: Equatable, Sendable {
    public let isStarted: Bool
    public let isSystemProxyEnabled: Bool
    public let isTunEnabled: Bool
    public let activeSystemTunnel: Bool
    public let egressKind: NetworkEgressKind
    public let externalIP: String
    public let countryCode: String
    public let countryName: String
    public let intranetIP: String
    public let httpPort: Int
    public let socksPort: Int
    public let selectedMode: OutboundMode
    public let selectedProfile: String
    public let portChecks: [NetworkPortCheck]
    public let dnsChecks: [NetworkDNSCheck]
    public let endpointChecks: [NetworkEndpointCheck]

    public init(
        isStarted: Bool,
        isSystemProxyEnabled: Bool,
        isTunEnabled: Bool,
        activeSystemTunnel: Bool,
        egressKind: NetworkEgressKind,
        externalIP: String,
        countryCode: String,
        countryName: String,
        intranetIP: String,
        httpPort: Int,
        socksPort: Int,
        selectedMode: OutboundMode,
        selectedProfile: String,
        portChecks: [NetworkPortCheck] = [],
        dnsChecks: [NetworkDNSCheck] = [],
        endpointChecks: [NetworkEndpointCheck] = []
    ) {
        self.isStarted = isStarted
        self.isSystemProxyEnabled = isSystemProxyEnabled
        self.isTunEnabled = isTunEnabled
        self.activeSystemTunnel = activeSystemTunnel
        self.egressKind = egressKind
        self.externalIP = externalIP
        self.countryCode = countryCode
        self.countryName = countryName
        self.intranetIP = intranetIP
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.selectedMode = selectedMode
        self.selectedProfile = selectedProfile
        self.portChecks = portChecks
        self.dnsChecks = dnsChecks
        self.endpointChecks = endpointChecks
    }
}

public struct NetworkPortTarget: Equatable, Sendable {
    public let label: String
    public let port: Int

    public init(label: String, port: Int) {
        self.label = label
        self.port = port
    }

    public static func standard(httpPort: Int, socksPort: Int, controllerPort: Int) -> [Self] {
        [
            NetworkPortTarget(label: "HTTP Proxy", port: httpPort),
            NetworkPortTarget(label: "Socks Proxy", port: socksPort),
            NetworkPortTarget(label: "Controller", port: controllerPort),
        ]
    }
}

public struct NetworkPortCheck: Equatable, Identifiable, Sendable {
    public var id: Int { port }
    public let label: String
    public let port: Int
    public let isListening: Bool
    public let ownerName: String?
    public let ownerPID: Int?

    public init(
        label: String,
        port: Int,
        isListening: Bool,
        ownerName: String? = nil,
        ownerPID: Int? = nil
    ) {
        self.label = label
        self.port = port
        self.isListening = isListening
        self.ownerName = ownerName
        self.ownerPID = ownerPID
    }

    public var ownerDescription: String {
        guard let ownerName else {
            return "No listener"
        }
        if let ownerPID {
            return "\(ownerName) pid \(ownerPID)"
        }
        return ownerName
    }
}

public enum NetworkPortProbe {
    public static func check(targets: [NetworkPortTarget]) async -> [NetworkPortCheck] {
        await Task.detached(priority: .utility) {
            targets.map { target in
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = [
                    "-nP",
                    "-iTCP:\(target.port)",
                    "-sTCP:LISTEN",
                ]
                process.standardOutput = output
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    return NetworkPortCheck(label: target.label, port: target.port, isListening: false)
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8) else {
                    return NetworkPortCheck(label: target.label, port: target.port, isListening: false)
                }
                return parse(output: text, targets: [target]).first
                    ?? NetworkPortCheck(label: target.label, port: target.port, isListening: false)
            }
        }.value
    }

    public static func parse(
        output: String,
        targets: [NetworkPortTarget]
    ) -> [NetworkPortCheck] {
        targets.map { target in
            guard let line = output
                .split(whereSeparator: \.isNewline)
                .first(where: { line in
                    line.contains(":\(target.port) ")
                        || line.contains(":\(target.port) (LISTEN)")
                }) else {
                return NetworkPortCheck(label: target.label, port: target.port, isListening: false)
            }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let ownerName = fields.first.map(String.init)
            let ownerPID = fields.dropFirst().first.flatMap { Int($0) }
            return NetworkPortCheck(
                label: target.label,
                port: target.port,
                isListening: true,
                ownerName: ownerName,
                ownerPID: ownerPID
            )
        }
    }
}

public struct NetworkDNSTarget: Equatable, Sendable {
    public let host: String

    public init(host: String) {
        self.host = host
    }

    public static let standard: [Self] = [
        NetworkDNSTarget(host: "ipwho.is"),
        NetworkDNSTarget(host: "api4.ipify.org"),
        NetworkDNSTarget(host: "github.com"),
    ]
}

public struct NetworkDNSCheck: Equatable, Identifiable, Sendable {
    public var id: String { host }
    public let host: String
    public let addresses: [String]
    public let errorMessage: String?

    public init(host: String, addresses: [String], errorMessage: String? = nil) {
        self.host = host
        self.addresses = addresses
        self.errorMessage = errorMessage
    }

    public var isResolved: Bool {
        !addresses.isEmpty && errorMessage == nil
    }

    public var detail: String {
        if isResolved {
            return addresses.prefix(3).joined(separator: ", ")
        }
        return errorMessage ?? "Resolution failed"
    }
}

public enum NetworkDNSProbe {
    public static func resolve(targets: [NetworkDNSTarget]) async -> [NetworkDNSCheck] {
        await Task.detached(priority: .utility) {
            targets.map(resolve)
        }.value
    }

    private static func resolve(target: NetworkDNSTarget) -> NetworkDNSCheck {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(target.host, nil, &hints, &result)
        guard status == 0, let result else {
            let message = String(cString: gai_strerror(status))
            return NetworkDNSCheck(host: target.host, addresses: [], errorMessage: message)
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<addrinfo>? = result
        while let current = pointer {
            if let address = stringAddress(from: current.pointee) {
                addresses.append(address)
            }
            pointer = current.pointee.ai_next
        }
        return NetworkDNSCheck(
            host: target.host,
            addresses: Array(NSOrderedSet(array: addresses).compactMap { $0 as? String })
        )
    }

    private static func stringAddress(from info: addrinfo) -> String? {
        guard let socketAddress = info.ai_addr else {
            return nil
        }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            socketAddress,
            info.ai_addrlen,
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else {
            return nil
        }
        let hostBytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: hostBytes, as: UTF8.self)
    }
}

public struct NetworkEndpointTarget: Equatable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    public static let standard: [Self] = [
        NetworkEndpointTarget(name: "ipwho.is", url: URL(string: "https://ipwho.is/")!),
        NetworkEndpointTarget(name: "api4.ipify", url: URL(string: "https://api4.ipify.org?format=json")!),
    ]
}

public struct NetworkEndpointCheck: Equatable, Identifiable, Sendable {
    public var id: String { url.absoluteString }
    public let name: String
    public let url: URL
    public let isReachable: Bool
    public let statusCode: Int?
    public let latencyMilliseconds: Int?
    public let errorMessage: String?

    public init(
        name: String,
        url: URL,
        isReachable: Bool,
        statusCode: Int?,
        latencyMilliseconds: Int?,
        errorMessage: String?
    ) {
        self.name = name
        self.url = url
        self.isReachable = isReachable
        self.statusCode = statusCode
        self.latencyMilliseconds = latencyMilliseconds
        self.errorMessage = errorMessage
    }

    public var statusDescription: String {
        if let statusCode {
            return "HTTP \(statusCode)"
        }
        return errorMessage ?? "Unavailable"
    }

    public var latencyDescription: String {
        guard let latencyMilliseconds else {
            return "--"
        }
        return "\(latencyMilliseconds) ms"
    }
}

public enum NetworkEndpointProbe {
    public static func check(targets: [NetworkEndpointTarget]) async -> [NetworkEndpointCheck] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        return await withTaskGroup(of: NetworkEndpointCheck.self) { group in
            for target in targets {
                group.addTask {
                    await check(target: target, session: session)
                }
            }

            var checks: [NetworkEndpointCheck] = []
            for await check in group {
                checks.append(check)
            }
            return targets.compactMap { target in
                checks.first { $0.url == target.url }
            }
        }
    }

    private static func check(
        target: NetworkEndpointTarget,
        session: URLSession
    ) async -> NetworkEndpointCheck {
        let startedAt = ContinuousClock.now
        do {
            let (_, response) = try await session.data(from: target.url)
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Int(
                Double(elapsed.components.seconds) * 1_000
                    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            )
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return NetworkEndpointCheck(
                name: target.name,
                url: target.url,
                isReachable: statusCode.map { (200..<400).contains($0) } ?? true,
                statusCode: statusCode,
                latencyMilliseconds: milliseconds,
                errorMessage: nil
            )
        } catch {
            return NetworkEndpointCheck(
                name: target.name,
                url: target.url,
                isReachable: false,
                statusCode: nil,
                latencyMilliseconds: nil,
                errorMessage: error.localizedDescription
            )
        }
    }
}

public struct NetworkDiagnosticFinding: Equatable, Identifiable, Sendable {
    public var id: String { "\(title)-\(detail)" }
    public let title: String
    public let detail: String
    public let severity: NetworkDiagnosticSeverity
    public let symbol: String
}

public struct NetworkDiagnosticEvidenceSection: Equatable, Sendable {
    public let title: String
    public let rows: [String]

    public init(title: String, rows: [String]) {
        self.title = title
        self.rows = rows
    }
}

public struct NetworkDiagnosticReport: Equatable, Sendable {
    public let summary: String
    public let severity: NetworkDiagnosticSeverity
    public let suggestedAction: String
    public let findings: [NetworkDiagnosticFinding]
    public let evidenceSections: [NetworkDiagnosticEvidenceSection]

    public static let placeholder = NetworkDiagnosticReport(
        summary: "Run Network Doctor",
        severity: .healthy,
        suggestedAction: "Diagnose the current route, proxy, tunnel, and visible exit IP.",
        findings: [],
        evidenceSections: []
    )

    public var copyText: String {
        var lines = [
            "Nexora Network Doctor",
            "Summary: \(summary)",
            "Severity: \(severity.rawValue)",
            "Action: \(suggestedAction)",
        ]
        if !findings.isEmpty {
            lines.append("Findings:")
        }
        lines.append(contentsOf: findings.map { "- \($0.title): \($0.detail)" })
        for section in evidenceSections where !section.rows.isEmpty {
            lines.append("")
            if section.rows.count == 1 {
                lines.append("\(section.title): \(section.rows[0])")
            } else {
                lines.append("\(section.title):")
                lines.append(contentsOf: section.rows.map { "- \($0)" })
            }
        }
        return lines.joined(separator: "\n")
    }
}

public struct NetworkDiagnosticBriefMetric: Equatable, Sendable {
    public let title: String
    public let value: String
    public let symbol: String

    public init(title: String, value: String, symbol: String) {
        self.title = title
        self.value = value
        self.symbol = symbol
    }
}

public struct NetworkDiagnosticBrief: Equatable, Sendable {
    public let headline: String
    public let detail: String
    public let severity: NetworkDiagnosticSeverity
    public let symbol: String
    public let metrics: [NetworkDiagnosticBriefMetric]

    public init(
        headline: String,
        detail: String,
        severity: NetworkDiagnosticSeverity,
        symbol: String,
        metrics: [NetworkDiagnosticBriefMetric]
    ) {
        self.headline = headline
        self.detail = detail
        self.severity = severity
        self.symbol = symbol
        self.metrics = metrics
    }

    public static func make(
        report: NetworkDiagnosticReport,
        totalChecks: Int,
        egressTitle: String,
        profileTitle: String,
        language: AppLanguage = .english
    ) -> Self {
        let headline: String
        let detail: String
        let focus = report.findings.first { $0.severity == .critical }
            ?? report.findings.first { $0.severity == .warning }
            ?? report.findings.first

        if report.findings.isEmpty {
            headline = language.text(.diagnosticReadyHeadline)
            detail = String(
                format: language.text(.diagnosticReadyDetailFormat),
                locale: language.locale,
                totalChecks
            )
        } else if report.severity == .critical {
            headline = language.text(.diagnosticBlockingHeadline)
            detail = String(
                format: language.text(.diagnosticResultDetailFormat),
                locale: language.locale,
                focus?.title ?? report.summary,
                totalChecks
            )
        } else if report.severity == .warning {
            headline = language.text(.diagnosticAttentionHeadline)
            detail = String(
                format: language.text(.diagnosticResultDetailFormat),
                locale: language.locale,
                focus?.title ?? report.summary,
                totalChecks
            )
        } else {
            headline = language.text(.diagnosticCleanHeadline)
            detail = String(
                format: language.text(.diagnosticResultDetailFormat),
                locale: language.locale,
                report.summary,
                totalChecks
            )
        }

        return NetworkDiagnosticBrief(
            headline: headline,
            detail: detail,
            severity: report.severity,
            symbol: report.severity.symbol,
            metrics: [
                NetworkDiagnosticBriefMetric(
                    title: language.text(.diagnosticChecks),
                    value: "\(totalChecks)",
                    symbol: "checklist"
                ),
                NetworkDiagnosticBriefMetric(
                    title: language.text(.diagnosticExit),
                    value: egressTitle,
                    symbol: "globe"
                ),
                NetworkDiagnosticBriefMetric(
                    title: language.text(.profile),
                    value: profileTitle,
                    symbol: "doc.text"
                ),
            ]
        )
    }
}

public enum NetworkDiagnosticEngine {
    public static func report(snapshot: NetworkDiagnosticSnapshot) -> NetworkDiagnosticReport {
        var findings: [NetworkDiagnosticFinding] = []

        if snapshot.externalIP == "Unavailable" || snapshot.egressKind == .unavailable {
            findings.append(NetworkDiagnosticFinding(
                title: "Exit lookup failed",
                detail: "Nexora could not fetch a fresh public IPv4 address, so stale country data was cleared.",
                severity: .critical,
                symbol: "xmark.octagon.fill"
            ))
        } else {
            let country = snapshot.countryName.isEmpty
                ? snapshot.countryCode
                : "\(snapshot.countryName) (\(snapshot.countryCode))"
            findings.append(NetworkDiagnosticFinding(
                title: "Visible exit",
                detail: "\(snapshot.externalIP) \(country)",
                severity: .healthy,
                symbol: "globe"
            ))
        }

        if snapshot.activeSystemTunnel {
            findings.append(NetworkDiagnosticFinding(
                title: "Broad utun route detected",
                detail: "macOS is routing public ranges through 198.18.x.x on a utun interface, so direct detection can still show the tunnel country.",
                severity: .warning,
                symbol: "point.3.connected.trianglepath.dotted"
            ))
        }

        if snapshot.isStarted {
            let fallback = snapshot.egressKind.diagnosticFallbackLabel
            let runtimeDetail = snapshot.egressKind == .proxy
                ? "Mihomo is active in \(snapshot.selectedMode.title) mode and the card is showing the proxy egress."
                : "Mihomo is active in \(snapshot.selectedMode.title) mode, but the visible exit fell back to \(fallback)."
            findings.append(NetworkDiagnosticFinding(
                title: "Nexora runtime",
                detail: runtimeDetail,
                severity: snapshot.egressKind == .proxy ? .healthy : .warning,
                symbol: "bolt.horizontal.circle.fill"
            ))
        } else {
            findings.append(NetworkDiagnosticFinding(
                title: "Nexora runtime",
                detail: "Mihomo is not started as the active VPN runtime.",
                severity: snapshot.activeSystemTunnel ? .warning : .healthy,
                symbol: "power.circle"
            ))
        }

        if snapshot.isSystemProxyEnabled || snapshot.isTunEnabled {
            let routes = [
                snapshot.isSystemProxyEnabled ? "system proxy :\(snapshot.httpPort)" : nil,
                snapshot.isTunEnabled ? "TUN" : nil,
            ].compactMap { $0 }.joined(separator: " + ")
            findings.append(NetworkDiagnosticFinding(
                title: "Nexora route switches",
                detail: routes.isEmpty ? "No Nexora route switch is active." : routes,
                severity: .healthy,
                symbol: "switch.2"
            ))
        }

        for check in snapshot.portChecks {
            if check.isListening {
                findings.append(NetworkDiagnosticFinding(
                    title: "\(check.label) :\(check.port)",
                    detail: check.ownerDescription,
                    severity: snapshot.isStarted ? .healthy : .warning,
                    symbol: "dot.radiowaves.left.and.right"
                ))
            } else if snapshot.isStarted {
                findings.append(NetworkDiagnosticFinding(
                    title: "\(check.label) :\(check.port)",
                    detail: "No process is listening even though the runtime is active.",
                    severity: .critical,
                    symbol: "xmark.octagon.fill"
                ))
            }
        }

        if !snapshot.dnsChecks.isEmpty {
            let failed = snapshot.dnsChecks.filter { !$0.isResolved }
            if failed.isEmpty {
                findings.append(NetworkDiagnosticFinding(
                    title: "DNS resolution",
                    detail: "Resolved \(snapshot.dnsChecks.count) hosts: \(snapshot.dnsChecks.map(\.host).joined(separator: ", "))",
                    severity: .healthy,
                    symbol: "network"
                ))
            } else {
                findings.append(NetworkDiagnosticFinding(
                    title: "DNS resolution",
                    detail: "Failed: \(failed.map { "\($0.host) (\($0.detail))" }.joined(separator: ", "))",
                    severity: .critical,
                    symbol: "network.slash"
                ))
            }
        }

        if !snapshot.endpointChecks.isEmpty {
            let failed = snapshot.endpointChecks.filter { !$0.isReachable }
            let slow = snapshot.endpointChecks.filter { ($0.latencyMilliseconds ?? 0) > 1_500 }
            if !failed.isEmpty {
                findings.append(NetworkDiagnosticFinding(
                    title: "External probes",
                    detail: "Failed: \(failed.map { "\($0.name) (\($0.statusDescription))" }.joined(separator: ", "))",
                    severity: .critical,
                    symbol: "antenna.radiowaves.left.and.right.slash"
                ))
            } else if !slow.isEmpty {
                findings.append(NetworkDiagnosticFinding(
                    title: "External probes",
                    detail: "Slow endpoints: \(slow.map { "\($0.name) \($0.latencyDescription)" }.joined(separator: ", "))",
                    severity: .warning,
                    symbol: "speedometer"
                ))
            } else {
                findings.append(NetworkDiagnosticFinding(
                    title: "External probes",
                    detail: snapshot.endpointChecks.map { "\($0.name) \($0.latencyDescription)" }.joined(separator: ", "),
                    severity: .healthy,
                    symbol: "checkmark.seal.fill"
                ))
            }
        }

        let severity = findings.contains(where: { $0.severity == .critical })
            ? NetworkDiagnosticSeverity.critical
            : findings.contains(where: { $0.severity == .warning })
                ? .warning
                : .healthy
        let summary: String
        let action: String
        if snapshot.activeSystemTunnel, snapshot.egressKind == .systemTunnel {
            summary = snapshot.isStarted
                ? "System tunnel is overriding Nexora proxy egress."
                : "System tunnel is controlling the visible egress."
            action = "Turn off the other VPN/TUN, then refresh."
        } else if severity == .critical {
            summary = "Network diagnosis found a blocking issue."
            action = "Fix the failed DNS, probe, or port check, then run again."
        } else if snapshot.isStarted, snapshot.egressKind == .proxy {
            summary = "Nexora proxy egress is active."
            action = "Switch node or mode if this exit is unexpected."
        } else if snapshot.isStarted, snapshot.egressKind == .direct {
            summary = "Nexora is running, but direct egress is visible."
            action = "Check Port Radar, then refresh."
        } else if snapshot.isStarted {
            summary = "Nexora is running, but \(snapshot.egressKind.diagnosticFallbackLabel) is visible."
            action = "Check the route and probes, then refresh."
        } else {
            summary = "Direct egress is visible."
            action = "No Nexora route conflict found."
        }

        return NetworkDiagnosticReport(
            summary: summary,
            severity: severity,
            suggestedAction: action,
            findings: findings,
            evidenceSections: evidenceSections(snapshot: snapshot)
        )
    }

    private static func evidenceSections(snapshot: NetworkDiagnosticSnapshot) -> [NetworkDiagnosticEvidenceSection] {
        let country = snapshot.countryName.isEmpty
            ? snapshot.countryCode
            : "\(snapshot.countryName) (\(snapshot.countryCode))"
        let routeDetails = [
            "profile=\(snapshot.selectedProfile)",
            "mode=\(snapshot.selectedMode.title)",
            "egress=\(snapshot.egressKind.rawValue)",
            "external=\(snapshot.externalIP)\(country.isEmpty ? "" : " \(country)")",
            "local=\(snapshot.intranetIP)",
            "started=\(snapshot.isStarted)",
            "systemProxy=\(snapshot.isSystemProxyEnabled)",
            "tun=\(snapshot.isTunEnabled)",
        ].joined(separator: ", ")

        var sections = [
            NetworkDiagnosticEvidenceSection(title: "Route", rows: [routeDetails]),
        ]

        if !snapshot.portChecks.isEmpty {
            sections.append(NetworkDiagnosticEvidenceSection(
                title: "Ports",
                rows: snapshot.portChecks.map { check in
                    if check.isListening {
                        return "\(check.label) :\(check.port) listening \(check.ownerDescription)"
                    }
                    return "\(check.label) :\(check.port) not listening"
                }
            ))
        }

        if !snapshot.dnsChecks.isEmpty {
            sections.append(NetworkDiagnosticEvidenceSection(
                title: "DNS",
                rows: snapshot.dnsChecks.map { check in
                    if check.isResolved {
                        return "\(check.host) \(check.detail)"
                    }
                    return "\(check.host) failed \(check.detail)"
                }
            ))
        }

        if !snapshot.endpointChecks.isEmpty {
            sections.append(NetworkDiagnosticEvidenceSection(
                title: "Endpoints",
                rows: snapshot.endpointChecks.map { check in
                    if check.isReachable {
                        return "\(check.name) \(check.statusDescription) \(check.latencyDescription)"
                    }
                    return "\(check.name) failed \(check.statusDescription)"
                }
            ))
        }

        return sections
    }
}

private extension NetworkEgressKind {
    var diagnosticFallbackLabel: String {
        switch self {
        case .detecting: "route detection"
        case .direct: "direct egress"
        case .proxy: "proxy egress"
        case .systemTunnel: "the system tunnel"
        case .unavailable: "an unavailable route"
        }
    }
}
