import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@MainActor
@Test(arguments: ["cancel", "route", "language", "newReport"])
func diagnosticExplanationDoesNotPublishAfterItsContextChanges(change: String) async throws {
    let gate = ExplanationGenerationGate()
    let fixture = try ExplanationLifecycleFixture(service: DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in await gate.wait(); return [0] }
    ))
    defer { gate.release(); fixture.cleanup() }
    await fixture.store.runNetworkDiagnosis()
    try #require(fixture.store.diagnosticExplanation?.source == .rules)
    let generation = Task { await fixture.store.explainNetworkDiagnosis() }
    try await gate.waitUntilStarted()
    #expect(fixture.store.isExplainingDiagnosis)
    switch change {
    case "cancel": fixture.store.cancelDiagnosticExplanation()
    case "route": fixture.store.selectedMode = .global
    case "language": fixture.store.language = .simplifiedChinese
    default: await fixture.store.runNetworkDiagnosis()
    }
    #expect(!fixture.store.isExplainingDiagnosis)
    gate.release()
    await generation.value
    if change == "route" {
        #expect(fixture.store.diagnosticExplanation?.source == .rules)
        #expect(fixture.store.isDiagnosticExplanationStale)
        #expect(fixture.store.diagnosticExplanationDate != nil)
        #expect(fixture.store.networkDiagnosticReportDate == nil)
    } else {
        #expect(fixture.store.diagnosticExplanation?.source == .rules)
        #expect(!fixture.store.isDiagnosticExplanationStale)
        #expect(fixture.store.networkDiagnosticReportDate != nil)
    }
    #expect(!fixture.store.diagnosticExplanationDidFallback)
}

@MainActor
@Test func diagnosticExplanationSharesAnInFlightRequestAndAcceptsOnlyTheCurrentResult() async throws {
    let gate = ExplanationGenerationGate()
    let fixture = try ExplanationLifecycleFixture(service: DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in await gate.wait(); return [0] }
    ))
    defer { gate.release(); fixture.cleanup() }
    await fixture.store.runNetworkDiagnosis()
    let first = Task { await fixture.store.explainNetworkDiagnosis() }
    try await gate.waitUntilStarted()
    await fixture.store.explainNetworkDiagnosis()
    #expect(gate.calls == 1)
    gate.release()
    await first.value
    #expect(fixture.store.diagnosticExplanation?.source == .onDeviceModel)
    #expect(!fixture.store.isExplainingDiagnosis)
}

@MainActor
@Test func diagnosticExplanationModelFailureKeepsTheRulesAndReportsFallback() async throws {
    let fixture = try ExplanationLifecycleFixture(service: DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in throw URLError(.cannotDecodeContentData) }
    ))
    defer { fixture.cleanup() }
    await fixture.store.runNetworkDiagnosis()
    let rules = fixture.store.diagnosticExplanation
    await fixture.store.explainNetworkDiagnosis()
    #expect(fixture.store.diagnosticExplanation == rules)
    #expect(fixture.store.diagnosticExplanationDidFallback)
    #expect(!fixture.store.isExplainingDiagnosis)
}

private final class ExplanationGenerationGate: Sendable {
    private struct State {
        var calls = 0
        var continuation: CheckedContinuation<Void, Never>?
        var isOpen = false
    }
    private let state = Mutex(State())
    var calls: Int { state.withLock { $0.calls } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadyOpen = state.withLock { state in
                state.calls += 1
                if state.isOpen { return true }
                state.continuation = continuation
                return false
            }
            if alreadyOpen { continuation.resume() }
        }
    }

    func release() {
        let continuation = state.withLock { state in
            state.isOpen = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while calls == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(calls == 1)
    }
}

@MainActor
private struct ExplanationLifecycleFixture {
    let directory: URL
    let store: AppStore
    let defaults: UserDefaults
    let identifier: String

    init(service: DiagnosticExplanationService) throws {
        identifier = "NexoraExplanation-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: identifier))
        let executable = directory.appendingPathComponent("identity-fixture")
        try """
        #!/bin/sh
        echo '{"success":true,"ip":"203.0.113.1","country_code":"US","country":"Fixture"}'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        store = AppStore(
            coreService: MihomoCoreService(coreBinaryURL: nil, privilegedTUN: nil),
            profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
            networkIdentityService: NetworkIdentityService(
                directFetcher: DirectNetworkIdentityFetcher(executableURL: executable),
                systemTunnelDetector: { false }
            ),
            networkPortProbe: { _ in [] }, networkDNSProbe: { _ in [] }, networkEndpointProbe: { _ in [] },
            diagnosticExplanationService: service, userDefaults: defaults,
            automaticallyMonitorsRuntime: false
        )
        store.language = .english
    }

    func cleanup() {
        store.shutdownForApplicationTermination()
        defaults.removePersistentDomain(forName: identifier)
        try? FileManager.default.removeItem(at: directory)
    }
}
