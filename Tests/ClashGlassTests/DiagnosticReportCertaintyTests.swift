import Foundation
import Testing
@testable import ClashGlassCore

@Test(arguments: [429, 503])
func diagnosticReportTreatsServiceHTTPFailuresAsLimitedEvidence(status: Int) throws {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(
        egress: .unavailable,
        externalIP: "Unavailable",
        endpoints: [certaintyEndpoint(status: status, reachable: false)]
    ))

    // An IP lookup and its HTTP probe can both fail on the same service. They
    // must not combine into a claim that the machine has no internet access.
    #expect(report.severity == .warning)
    let probe = try #require(report.findings.first { $0.title == "External probes" })
    #expect(probe.severity == .warning)
    #expect(probe.detail.contains("HTTP \(status)"))
    #expect(!report.summary.localizedCaseInsensitiveContains("blocking"))
    #expect(!report.suggestedAction.localizedCaseInsensitiveContains("restart"))
}

@Test func diagnosticReportPreservesASuccessfulProbeAlongsideARateLimit() {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(endpoints: [
        certaintyEndpoint(status: 429, reachable: false),
        certaintyEndpoint(status: 200, reachable: true),
    ]))
    #expect(report.severity == .warning)
    #expect(report.copyText.contains("HTTP 200"))
    #expect(report.copyText.contains("HTTP 429"))
}

@Test func diagnosticReportStillFlagsATransportFailure() throws {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(endpoints: [
        certaintyEndpoint(status: nil, reachable: false),
    ]))
    let probe = try #require(report.findings.first { $0.title == "External probes" })
    #expect(probe.severity == .critical)
    #expect(report.severity == .critical)
}

@Test func diagnosticReportDoesNotTreatMissingExitMetadataAsABlockingProbe() {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(
        egress: .unavailable, externalIP: "Unavailable"
    ))
    #expect(report.severity == .warning)
    #expect(report.findings.first { $0.title == "Exit lookup failed" }?.severity == .warning)
}

@Test func diagnosticReportDoesNotBlameAnotherVPNForItsOwnTUNSetting() {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(
        tun: true, activeSystemTunnel: true, egress: .systemTunnel
    ))
    #expect(report.summary.contains("Nexora TUN"))
    #expect(!report.copyText.localizedCaseInsensitiveContains("overriding"))
    #expect(!report.suggestedAction.localizedCaseInsensitiveContains("other VPN"))
    #expect(!report.suggestedAction.localizedCaseInsensitiveContains("turn off"))
    #expect(report.findings.contains { $0.title.contains("utun") })
}

@Test func diagnosticReportDoesNotInferTunnelOwnershipFromARoute() {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(
        activeSystemTunnel: true, egress: .systemTunnel
    ))
    #expect(report.summary.contains("unverified"))
    #expect(!report.copyText.localizedCaseInsensitiveContains("overriding"))
    #expect(!report.suggestedAction.localizedCaseInsensitiveContains("turn off"))
}

@Test(arguments: [true, false])
func diagnosticReportDoesNotInventPortConflictsWhenAPIDIsUnknown(corePIDKnown: Bool) throws {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(
        started: false,
        egress: .direct,
        ports: [.init(
            label: "HTTP Proxy", port: 7890, isListening: true,
            ownerName: corePIDKnown ? nil : "mihomo",
            ownerPID: corePIDKnown ? nil : 99
        )],
        corePID: corePIDKnown ? 42 : nil
    ))
    let port = try #require(report.findings.first { $0.title == "HTTP Proxy :7890" })
    #expect(port.severity == .warning)
    #expect(port.detail.localizedCaseInsensitiveContains("could not be verified"))
    #expect(!report.summary.localizedCaseInsensitiveContains("another process"))
    #expect(!port.detail.contains("No listener"))
}

@Test func diagnosticReportKeepsKnownPortOwnershipConflictsCritical() throws {
    let report = NetworkDiagnosticEngine.report(snapshot: certaintySnapshot(ports: [
        .init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: "mihomo", ownerPID: 99),
    ]))
    let port = try #require(report.findings.first { $0.title == "HTTP Proxy :7890" })
    #expect(report.severity == .critical)
    #expect(port.severity == .critical)
    #expect(report.copyText.contains("pid 99"))
    #expect(report.copyText.contains("corePID=42"))
}

private func certaintySnapshot(
    started: Bool = true,
    tun: Bool = false,
    activeSystemTunnel: Bool = false,
    egress: NetworkEgressKind = .proxy,
    externalIP: String = "203.0.113.10",
    ports: [NetworkPortCheck] = [
        .init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: "mihomo", ownerPID: 42),
    ],
    corePID: Int? = 42,
    endpoints: [NetworkEndpointCheck] = []
) -> NetworkDiagnosticSnapshot {
    NetworkDiagnosticSnapshot(
        isStarted: started, isSystemProxyEnabled: started, isTunEnabled: tun,
        activeSystemTunnel: activeSystemTunnel, egressKind: egress,
        externalIP: externalIP, countryCode: "US", countryName: "United States",
        intranetIP: "192.0.2.10", httpPort: 7890, socksPort: 7891,
        selectedMode: .rule, selectedProfile: "Fixture",
        portChecks: ports, endpointChecks: endpoints, coreProcessID: corePID
    )
}

private func certaintyEndpoint(status: Int?, reachable: Bool) -> NetworkEndpointCheck {
    NetworkEndpointCheck(
        name: "Fixture \(status ?? 0)",
        url: URL(string: "https://example.com/\(status ?? 0)")!,
        isReachable: reachable, statusCode: status,
        latencyMilliseconds: status == nil ? nil : 100,
        errorMessage: status == nil ? "Timed out" : nil
    )
}
