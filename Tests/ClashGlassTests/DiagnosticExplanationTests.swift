import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@Test func diagnosticExplanationTreatsRateLimitingAsAProbeLimitation() {
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(endpointChecks: [
            explanationEndpoint(status: 429, isReachable: false, privateMarker: "rate-limited-probe"),
            explanationEndpoint(status: 200, isReachable: true, privateMarker: "working-probe"),
        ]),
        hasSystemProxyError: false
    )
    let result = DiagnosticExplanationService().ruleExplanation(context: context, language: .english)

    #expect(context.rateLimitedEndpointCount == 1)
    #expect(context.reachableEndpointCount == 1)
    #expect(context.transportFailureCount == 0)
    #expect(result.summary.contains("HTTP 429 does not establish a VPN outage"))
    #expect(result.observations.contains { $0.contains("external probes succeeded") })
    #expect(result.nextSteps.contains { $0.contains("Retry rate-limited probes later") })
}

@Test func diagnosticExplanationDoesNotMisidentifyNexorasOwnTUNAsAnotherVPN() {
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(isTunEnabled: true, activeSystemTunnel: true),
        hasSystemProxyError: false
    )
    let result = DiagnosticExplanationService().ruleExplanation(context: context, language: .english)

    #expect(context.systemTunnelDetected)
    #expect(result.observations.contains { $0.contains("does not establish a second VPN") })
    #expect(!result.nextSteps.contains { $0.contains("other VPN/TUN apps") })
}

@Test func diagnosticExplanationTreatsAnExternalTunnelAsAPossibilityRatherThanAProvenOverride() {
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(activeSystemTunnel: true, egressKind: .systemTunnel),
        hasSystemProxyError: false
    )
    let result = DiagnosticExplanationService().ruleExplanation(context: context, language: .english)

    #expect(result.observations.contains { $0.contains("do not prove it overrides Nexora") })
    #expect(result.nextSteps.contains { $0.contains("change only one connection setting at a time") })
}

@Test(arguments: [Int?.none, Int?.some(99)])
func diagnosticExplanationDoesNotInventAPortConflictWhenCorePIDIsUnknown(ownerPID: Int?) {
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(
            portChecks: [.init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: "arbitrary-private-process", ownerPID: ownerPID)],
            coreProcessID: nil
        ),
        hasSystemProxyError: false
    )
    let result = DiagnosticExplanationService().ruleExplanation(context: context, language: .english)

    #expect(context.foreignListenerCount == 0)
    #expect(context.unknownListenerOwnerCount == 1)
    #expect(result.observations.contains { $0.contains("does not establish a port conflict") })
    #expect(!result.nextSteps.contains { $0.contains("release or change a port") })
}

@Test func diagnosticExplanationDirectsMissingListenerChecksToTheLocalCore() {
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(portChecks: [
            .init(label: "HTTP Proxy", port: 7890, isListening: false),
            .init(label: "Controller", port: 9090, isListening: true, ownerName: "mihomo", ownerPID: 42),
        ]),
        hasSystemProxyError: false
    )
    let result = DiagnosticExplanationService().ruleExplanation(context: context, language: .english)

    #expect(context.missingListenerCount == 1)
    #expect(result.summary.contains("Expected local core listeners are missing"))
    #expect(result.nextSteps.contains { $0.contains("restarting the core") })
}

@Test func diagnosticExplanationDoesNotAssignSystemDNSFailuresToMihomoWithoutEvidence() {
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(dnsChecks: [
            .init(host: "private.invalid", addresses: [], errorMessage: "private DNS error"),
        ]),
        hasSystemProxyError: false
    )
    let result = DiagnosticExplanationService().ruleExplanation(context: context, language: .english)

    #expect(context.dnsFailureCount == 1)
    #expect(result.observations.contains { $0.contains("macOS resolver, not Mihomo DNS in isolation") })
}

@Test func diagnosticExplanationContextRedactsPrivateStringsBeforeSerialization() throws {
    func context(marker: String) -> DiagnosticExplanationContext {
        DiagnosticExplanationContext(
            snapshot: explanationSnapshot(
                portChecks: [
                    .init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: marker, ownerPID: 42),
                    .init(label: "Controller", port: 9090, isListening: true, ownerName: marker, ownerPID: 42),
                ],
                dnsChecks: [
                    .init(host: marker + ".invalid", addresses: [], errorMessage: marker + "-raw-DNS-error"),
                ],
                endpointChecks: [explanationEndpoint(status: 429, isReachable: false, privateMarker: marker)],
                privateMarker: marker
            ),
            hasSystemProxyError: true
        )
    }

    let first = context(marker: "CONFIDENTIAL_PROFILE_AND_ERROR_A")
    let second = context(marker: "CONFIDENTIAL_PROFILE_AND_ERROR_B")
    // Changing only private labels, addresses, URL tokens, and raw errors must
    // not change the allowlisted evidence supplied to the local model.
    #expect(first == second)
    let serialized = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
    #expect(!serialized.contains("CONFIDENTIAL"))
    #expect(!first.sanitizedJSON.contains("CONFIDENTIAL"))
    #expect(!serialized.contains(".invalid"))
    #expect(!first.sanitizedJSON.contains("token="))
}

@Test(arguments: [
    DiagnosticModelAvailability.unsupportedSystem,
    .intelligenceDisabled,
    .modelNotReady,
    .deviceIneligible,
    .unavailable,
])
func diagnosticExplanationUnavailableModelReturnsRulesWithoutGenerating(reason: DiagnosticModelAvailability) async throws {
    let calls = Mutex(0)
    let service = DiagnosticExplanationService(
        availability: { reason },
        generate: { _ in calls.withLock { $0 += 1 }; return [0] }
    )
    let context = DiagnosticExplanationContext(snapshot: explanationSnapshot(), hasSystemProxyError: false)

    let result = try await service.explain(context: context, language: .english)

    #expect(service.availability() == reason)
    #expect(result == service.ruleExplanation(context: context, language: .english))
    #expect(result.source == .rules)
    #expect(calls.withLock { $0 } == 0)
}

@Test func diagnosticExplanationGenerationFailureKeepsTheCompleteRuleResult() async throws {
    let service = DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in throw DiagnosticExplanationFixtureError.generationFailed }
    )
    let context = DiagnosticExplanationContext(snapshot: explanationSnapshot(), hasSystemProxyError: true)

    let result = try await service.explain(context: context, language: .simplifiedChinese)

    #expect(result == service.ruleExplanation(context: context, language: .simplifiedChinese))
    #expect(!result.summary.isEmpty)
    #expect(!result.observations.isEmpty)
    #expect(!result.nextSteps.isEmpty)
}

@Test(arguments: [[Int](), [99], [-1], [1]])
func diagnosticExplanationRejectsInvalidModelCandidateIndexes(indexes: [Int]) async throws {
    let service = DiagnosticExplanationService(availability: { .available }, generate: { _ in indexes })
    let context = DiagnosticExplanationContext(snapshot: explanationSnapshot(), hasSystemProxyError: true)

    let result = try await service.explain(context: context, language: .english)

    #expect(result == service.ruleExplanation(context: context, language: .english))
}

@Test func diagnosticExplanationModelCanSelectOnlyExistingRuleConclusions() async throws {
    let receivedPrompt = Mutex("")
    let service = DiagnosticExplanationService(
        availability: { .available },
        generate: { prompt in receivedPrompt.withLock { $0 = prompt }; return [0] }
    )
    let context = DiagnosticExplanationContext(
        snapshot: explanationSnapshot(privateMarker: "PRIVATE_NODE_TOKEN_SUBSCRIPTION"),
        hasSystemProxyError: true
    )
    let rules = service.ruleExplanation(context: context, language: .english)

    let result = try await service.explain(context: context, language: .english)

    #expect(result.source == .onDeviceModel)
    #expect(result.summary == rules.summary)
    #expect(result.observations == rules.observations)
    #expect(result.nextSteps == rules.nextSteps)
    #expect(!receivedPrompt.withLock { $0 }.contains("PRIVATE_NODE_TOKEN_SUBSCRIPTION"))
    #expect(!receivedPrompt.withLock { $0 }.isEmpty)
}

@Test func diagnosticExplanationTimeoutReturnsRulesBeforeAnUncooperativeModelCompletes() async throws {
    let gate = ExplanationGenerationGate()
    let service = DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in try await gate.response() },
        maximumGenerationDuration: .milliseconds(20)
    )
    let context = DiagnosticExplanationContext(snapshot: explanationSnapshot(), hasSystemProxyError: true)
    // A watchdog keeps an incorrectly structured timeout implementation from
    // hanging the test suite while still failing its latency/source assertions.
    let watchdog = Task {
        try? await Task.sleep(for: .seconds(3))
        await gate.finish(.success([0]))
    }
    defer { watchdog.cancel() }
    let startedAt = ContinuousClock.now
    let result = try await service.explain(context: context, language: .english)
    let elapsed = startedAt.duration(to: .now)
    await gate.finish(.success([0]))

    #expect(result == service.ruleExplanation(context: context, language: .english))
    #expect(elapsed < .seconds(2))
}

@Test func diagnosticExplanationCancellationIsNotConvertedIntoFallbackSuccess() async throws {
    let service = DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in throw CancellationError() }
    )
    let context = DiagnosticExplanationContext(snapshot: explanationSnapshot(), hasSystemProxyError: false)

    do {
        _ = try await service.explain(context: context, language: .english)
        Issue.record("A canceled model request must not publish a rule result as a completed explanation.")
    } catch is CancellationError {
        // Expected: AppStore can discard the canceled task without a stale result.
    }
}

@Test(arguments: [false, true])
func diagnosticExplanationDiscardsLateModelResultsAfterCancellation(modelFails: Bool) async throws {
    let gate = ExplanationGenerationGate()
    let service = DiagnosticExplanationService(
        availability: { .available },
        generate: { _ in try await gate.response() }
    )
    let context = DiagnosticExplanationContext(snapshot: explanationSnapshot(), hasSystemProxyError: false)
    let request = Task { try await service.explain(context: context, language: .english) }
    await gate.waitUntilRequested()
    request.cancel()
    // Some model backends finish or report a generic error after cancellation.
    // Neither path may become a successful, now-stale explanation.
    await gate.finish(modelFails ? .failure(.generationFailed) : .success([0]))

    do {
        _ = try await request.value
        Issue.record("A late model completion must not publish after cancellation.")
    } catch is CancellationError {
        // Expected for both a late value and a late non-cancellation error.
    }
}

private enum DiagnosticExplanationFixtureError: Error {
    case generationFailed
}

private actor ExplanationGenerationGate {
    private var requested = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<[Int], Error>?

    func response() async throws -> [Int] {
        requested = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        return try await withCheckedThrowingContinuation { completion = $0 }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(_ result: Result<[Int], DiagnosticExplanationFixtureError>) {
        switch result {
        case let .success(indexes): completion?.resume(returning: indexes)
        case let .failure(error): completion?.resume(throwing: error)
        }
        completion = nil
    }
}

private func explanationSnapshot(
    isStarted: Bool = true,
    isTunEnabled: Bool = false,
    activeSystemTunnel: Bool = false,
    egressKind: NetworkEgressKind = .proxy,
    portChecks: [NetworkPortCheck] = [
        .init(label: "HTTP Proxy", port: 7890, isListening: true, ownerName: "mihomo", ownerPID: 42),
        .init(label: "Controller", port: 9090, isListening: true, ownerName: "mihomo", ownerPID: 42),
    ],
    dnsChecks: [NetworkDNSCheck] = [
        .init(host: "probe.example", addresses: ["203.0.113.1"]),
    ],
    endpointChecks: [NetworkEndpointCheck] = [],
    coreProcessID: Int? = 42,
    privateMarker: String = "private-fixture"
) -> NetworkDiagnosticSnapshot {
    NetworkDiagnosticSnapshot(
        isStarted: isStarted,
        isSystemProxyEnabled: isStarted,
        isTunEnabled: isTunEnabled,
        activeSystemTunnel: activeSystemTunnel,
        egressKind: egressKind,
        externalIP: privateMarker + "-external-IP",
        countryCode: privateMarker + "-country-code",
        countryName: privateMarker + "-country-name",
        intranetIP: privateMarker + "-intranet-IP",
        httpPort: 7890,
        socksPort: 7891,
        selectedMode: .rule,
        selectedProfile: privateMarker + "-subscription",
        portChecks: portChecks,
        dnsChecks: dnsChecks,
        endpointChecks: endpointChecks,
        coreProcessID: coreProcessID
    )
}

private func explanationEndpoint(
    status: Int?,
    isReachable: Bool,
    privateMarker: String = "private-fixture"
) -> NetworkEndpointCheck {
    NetworkEndpointCheck(
        name: privateMarker + "-probe-name",
        url: URL(string: "https://\(privateMarker).invalid/probe?token=\(privateMarker)")!,
        isReachable: isReachable,
        statusCode: status,
        latencyMilliseconds: isReachable ? 120 : nil,
        errorMessage: isReachable ? nil : privateMarker + "-raw-error"
    )
}

private func explanationText(_ explanation: DiagnosticExplanation) -> String {
    ([explanation.summary] + explanation.observations + explanation.nextSteps)
        .joined(separator: "\n")
}
