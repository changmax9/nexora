import Foundation

public enum DiagnosticExplanationSource: String, Equatable, Sendable {
    case rules
    case onDeviceModel
}

public struct DiagnosticExplanation: Equatable, Sendable {
    public let summary: String
    public let observations: [String]
    public let nextSteps: [String]
    public let source: DiagnosticExplanationSource

    public init(
        summary: String,
        observations: [String],
        nextSteps: [String],
        source: DiagnosticExplanationSource = .rules
    ) {
        self.summary = summary
        self.observations = observations
        self.nextSteps = nextSteps
        self.source = source
    }
}

public enum DiagnosticModelAvailability: Equatable, Sendable {
    case available
    case unsupportedSystem
    case intelligenceDisabled
    case modelNotReady
    case deviceIneligible
    case unavailable
}

/// Only allowlisted states and aggregate counts leave the diagnostic snapshot.
/// This value cannot retain IPs, hostnames, URLs, profile or process names,
/// subscription content, raw error messages, or logs.
public struct DiagnosticExplanationContext: Codable, Equatable, Sendable {
    public enum Egress: String, Codable, Sendable {
        case detecting
        case direct
        case proxy
        case systemTunnel
        case unavailable
    }

    public enum Mode: String, Codable, Sendable {
        case rule
        case global
        case direct
    }

    public let schemaVersion: Int
    public let runtimeActive: Bool
    public let systemProxyEnabled: Bool
    public let tunEnabled: Bool
    public let systemTunnelDetected: Bool
    public let egress: Egress
    public let mode: Mode
    public let exitLookupFailed: Bool
    public let hasSystemProxyError: Bool
    public let expectsCoreListeners: Bool
    public let listenerCheckCount: Int
    public let missingListenerCount: Int
    public let foreignListenerCount: Int
    public let unknownListenerOwnerCount: Int
    public let dnsCheckCount: Int
    public let dnsFailureCount: Int
    public let endpointCheckCount: Int
    public let reachableEndpointCount: Int
    public let rateLimitedEndpointCount: Int
    public let otherHTTPFailureCount: Int
    public let transportFailureCount: Int
    public let slowEndpointCount: Int

    public init(snapshot: NetworkDiagnosticSnapshot, hasSystemProxyError: Bool) {
        schemaVersion = 1
        runtimeActive = snapshot.isStarted
        systemProxyEnabled = snapshot.isSystemProxyEnabled
        tunEnabled = snapshot.isTunEnabled
        systemTunnelDetected = snapshot.activeSystemTunnel
        egress = Egress(rawValue: snapshot.egressKind.rawValue) ?? .unavailable
        mode = Mode(rawValue: snapshot.selectedMode.rawValue) ?? .rule
        exitLookupFailed = snapshot.egressKind == .unavailable || snapshot.externalIP == "Unavailable"
        self.hasSystemProxyError = hasSystemProxyError
        expectsCoreListeners = snapshot.isStarted || snapshot.coreProcessID != nil
        listenerCheckCount = snapshot.portChecks.count
        missingListenerCount = snapshot.portChecks.filter { !$0.isListening }.count
        foreignListenerCount = snapshot.portChecks.filter { check in
            guard check.isListening, let expected = snapshot.coreProcessID,
                  let actual = check.ownerPID else { return false }
            return expected != actual
        }.count
        unknownListenerOwnerCount = snapshot.portChecks.filter { check in
            check.isListening && (snapshot.coreProcessID == nil || check.ownerPID == nil)
        }.count
        dnsCheckCount = snapshot.dnsChecks.count
        dnsFailureCount = snapshot.dnsChecks.filter { !$0.isResolved }.count
        endpointCheckCount = snapshot.endpointChecks.count
        reachableEndpointCount = snapshot.endpointChecks.filter(\.isReachable).count
        rateLimitedEndpointCount = snapshot.endpointChecks.filter { $0.statusCode == 429 }.count
        otherHTTPFailureCount = snapshot.endpointChecks.filter {
            !$0.isReachable && $0.statusCode != nil && $0.statusCode != 429
        }.count
        transportFailureCount = snapshot.endpointChecks.filter {
            !$0.isReachable && $0.statusCode == nil
        }.count
        slowEndpointCount = snapshot.endpointChecks.filter {
            $0.isReachable && ($0.latencyMilliseconds ?? 0) > 1_500
        }.count
    }

    public var sanitizedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
