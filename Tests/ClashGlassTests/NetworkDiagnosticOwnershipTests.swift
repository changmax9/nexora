import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@Test(arguments: [false, true])
func networkDoctorRecognizesItsOwnListenersWithOrWithoutVPN(isStarted: Bool) {
    let report = NetworkDiagnosticEngine.report(snapshot: ownershipSnapshot(
        isStarted: isStarted,
        checks: [.init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: "mihomo", ownerPID: 42)]
    ))
    #expect(report.severity == .healthy)
    #expect(report.findings.first(where: { $0.title == "HTTP Proxy :7890" })?.severity == .healthy)
    #expect(report.copyText.contains("corePID=42"))
    if !isStarted { #expect(report.copyText.contains("controller-only")) }
}

@Test(arguments: [false, true])
func networkDoctorDoesNotTrustAnotherMihomoProcess(isStarted: Bool) {
    let report = NetworkDiagnosticEngine.report(snapshot: ownershipSnapshot(
        isStarted: isStarted,
        checks: [.init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: "mihomo", ownerPID: 99)]
    ))
    #expect(report.severity == (isStarted ? .critical : .warning))
    if !isStarted {
        #expect(report.summary.contains("Another process"))
        #expect(!report.suggestedAction.contains("No Nexora route conflict"))
    }
}

@Test func networkDoctorRequiresTheControllerOnlyCoresExpectedListeners() {
    let report = NetworkDiagnosticEngine.report(snapshot: ownershipSnapshot(
        isStarted: false,
        checks: [.init(label: "Controller", port: 9090, isListening: false)]
    ))
    #expect(report.severity == .critical)
    #expect(report.findings.first(where: { $0.title == "Controller :9090" })?.severity == .critical)
}

@MainActor
@Test func simultaneousNetworkDiagnosesDoNotRunDuplicateProbes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = directory.appendingPathComponent("fake-curl")
    try """
    #!/bin/sh
    echo '{"success":true,"ip":"203.0.113.1","country_code":"US","country":"United States"}'
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let calls = Mutex(0)
    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
        networkIdentityService: NetworkIdentityService(
            directFetcher: DirectNetworkIdentityFetcher(executableURL: executable),
            systemTunnelDetector: { false }
        ),
        networkPortProbe: { targets in
            calls.withLock { $0 += 1 }
            try? await Task.sleep(for: .milliseconds(150))
            return targets.map { .init(label: $0.label, port: $0.port, isListening: false) }
        },
        networkDNSProbe: { _ in [] }, networkEndpointProbe: { _ in [] }
    )
    let first = Task { await store.runNetworkDiagnosis() }
    for _ in 0..<1_000 {
        if store.isRunningNetworkDiagnosis { break }
        await Task.yield()
    }
    #expect(store.isRunningNetworkDiagnosis)
    await store.runNetworkDiagnosis()
    #expect(store.isRunningNetworkDiagnosis)
    await first.value
    #expect(!store.isRunningNetworkDiagnosis)
    #expect(calls.withLock { $0 } == 1)
    #expect(store.networkDiagnosticReport.severity == .healthy)
}

private func ownershipSnapshot(isStarted: Bool, checks: [NetworkPortCheck]) -> NetworkDiagnosticSnapshot {
    NetworkDiagnosticSnapshot(
        isStarted: isStarted, isSystemProxyEnabled: isStarted, isTunEnabled: false,
        activeSystemTunnel: false, egressKind: isStarted ? .proxy : .direct,
        externalIP: "203.0.113.1", countryCode: "US", countryName: "United States",
        intranetIP: "192.168.1.2", httpPort: 7890, socksPort: 7891,
        selectedMode: .rule, selectedProfile: "Local",
        portChecks: checks, coreProcessID: 42
    )
}
