import Darwin
import Foundation
import NexoraTUNSupport
import Testing
@testable import ClashGlassCore

private let tunProfile = """
mixed-port: 17890
external-controller: 127.0.0.1:19090
allow-lan: true
external-controller-unix: /tmp/untrusted.sock
external-ui: /tmp/untrusted-ui
proxies: []
proxy-groups: []
rules: [MATCH,DIRECT]
"""

@Test func tunConfigurationCreatesAuthenticatedLoopbackRuntime() throws {
    let secret = UUID().uuidString + UUID().uuidString
    let yaml = try TUNConfiguration.normalized(yaml: tunProfile, secret: secret)
    let settings = try MihomoConfigurationInspector.inspect(yaml: yaml)
    #expect(settings.secret == secret)
    #expect(settings.tunEnabled)
    #expect(!yaml.contains("untrusted"))
    #expect(yaml.contains("stack: gvisor"))
    #expect(yaml.contains("auto-route: true"))
    #expect(yaml.contains("auto-detect-interface: true"))
    #expect(yaml.contains("allow-lan: false"))
    #expect(yaml.contains("dns-hijack:"))
    #expect(!tunProfile.contains(secret))
    #expect(!(try TUNConfiguration.validateAtBoundary(Data(yaml.utf8))).isEmpty)
}

@Test func tunBoundaryRejectsMissingSecret() {
    #expect(throws: (any Error).self) { try TUNConfiguration.validateAtBoundary(Data(tunProfile.utf8)) }
}

@Test(arguments: ["0.0.0.0:19090", "127.0.0.1:22", "localhost:19090"])
func tunBoundaryRejectsPublicOrPrivilegedController(_ address: String) {
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: tunProfile.replacingOccurrences(of: "127.0.0.1:19090", with: address), secret: UUID().uuidString)
    }
}

@Test(arguments: ["/etc/sudoers", "../../outside", "~/outside", "../outside"])
func tunBoundaryRejectsProviderPathEscape(_ path: String) {
    let profile = tunProfile + "\nproxy-providers:\n  remote:\n    type: http\n    url: https://example.com/proxies.yaml\n    path: '\(path)'\n"
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: profile, secret: UUID().uuidString)
    }
}

@Test func tunBoundaryRejectsExternalFileProviders() {
    let profile = tunProfile + "\nproxy-providers:\n  local:\n    type: file\n    path: local.yaml\n"
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: profile, secret: UUID().uuidString)
    }
}

@Test func tunBoundaryRejectsOversizedConfiguration() {
    #expect(throws: (any Error).self) {
        try TUNConfiguration.validateAtBoundary(Data(repeating: 65, count: TUNConfiguration.maximumSize + 1))
    }
}

@Test func tunBoundaryRejectsPrivilegedCertificateFileReads() {
    let yaml = tunProfile.replacingOccurrences(of: "proxies: []", with: "proxies:\n  - name: tls\n    type: trojan\n    certificate: /var/root/private.pem")
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: yaml, secret: UUID().uuidString)
    }
}

@MainActor
final class FakePrivilegedTUNRuntime: PrivilegedTUNRuntime {
    var isRunning = false { didSet { onRunningChange?(isRunning) } }
    var onRunningChange: ((Bool) -> Void)?
    var onUnexpectedTermination: ((String) -> Void)?
    var output = ""
    func runtimeOutput() async -> String { output }
    var rejectAuthorization = false
    var rejectStart = false
    var startCount = 0
    var stopCount = 0
    func authorize() throws {
        if rejectAuthorization { throw TUNServiceError("fixture: approval required") }
    }
    func start(configuration: Data) async throws {
        startCount += 1
        if rejectStart { throw TUNServiceError("fixture: privileged launch rejected") }
        isRunning = true
    }
    func stop() async { stopCount += 1; isRunning = false }
    func invalidate() { isRunning = false }
}

@MainActor
@Test func tunStartupReportsRouteConflictWithoutMislabelingOtherErrors() async {
    let runtime = FakePrivilegedTUNRuntime()
    runtime.isRunning = true
    let core = MihomoCoreService(coreBinaryURL: nil, privilegedTUN: runtime)
    runtime.output = "Start TUN listening error: configure tun interface: add route: 1.0.0.0/8: file exists"
    #expect(await core.tunStartupFailure() == "Another VPN or TUN connection already owns the required routes. Turn off its TUN mode before enabling Nexora TUN.")
    runtime.output = "Start TUN listening error: permission denied"
    #expect(await core.tunStartupFailure() == runtime.output)
    runtime.output = "info: controller ready"
    #expect(await core.tunStartupFailure() == nil)
}

@MainActor
@Test func disconnectedXPCServiceDoesNotCrashOnBackgroundErrorCallback() async {
    let connection = NSXPCConnection(machServiceName: "com.maxchang.Nexora.Tests.Missing.\(UUID().uuidString)")
    connection.remoteObjectInterface = NSXPCInterface(with: TUNHelperProtocol.self)
    connection.resume()
    let service = PrivilegedTUNService(connection: connection)
    #expect(await service.runtimeOutput().isEmpty)
    service.invalidate()
    #expect(!service.isRunning)
}

@Test func tunServiceIdentityRequirementValidatesTeamIdentifier() throws {
    let valid = try TUNServiceIdentity.requirement(
        identifier: "com.maxchang.Nexora",
        teamIdentifier: "WW3RYA2Y7G"
    )
    #expect(valid == "anchor apple generic and identifier \"com.maxchang.Nexora\" and certificate leaf[subject.OU] = \"WW3RYA2Y7G\"")
    #expect(throws: (any Error).self) {
        try TUNServiceIdentity.requirement(identifier: "com.maxchang.Nexora", teamIdentifier: "invalid-team!")
    }
}

@Test func tunExecutableSnapshotDetectsReplacementAndDeletion() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tun-snapshot-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let targetURL = tempDir.appendingPathComponent("NexoraTUNHelper")
    let stagedURL = tempDir.appendingPathComponent("NexoraTUNHelper.new")
    try Data("v1".utf8).write(to: targetURL)
    try Data("v2".utf8).write(to: stagedURL)

    let snapshot = try #require(TUNExecutableSnapshot.capture(path: targetURL.path))
    #expect(snapshot.matchesCurrentOnDisk())

    #expect(Darwin.rename(stagedURL.path, targetURL.path) == 0)
    #expect(!snapshot.matchesCurrentOnDisk())

    let updatedSnapshot = try #require(TUNExecutableSnapshot.capture(path: targetURL.path))
    #expect(updatedSnapshot != snapshot)
    #expect(updatedSnapshot.matchesCurrentOnDisk())

    try FileManager.default.removeItem(at: targetURL)
    #expect(!updatedSnapshot.matchesCurrentOnDisk())
    #expect(TUNExecutableSnapshot.capture(path: targetURL.path) == nil)
}

@Test func tunHelperLifecyclePolicyHandlesStaleAndMinimumRuntime() {
    #expect(!TUNHelperLifecyclePolicy.shouldRejectAndExitOnIncomingConnection(binaryMatchesOnDisk: true, hasActiveProcess: false))
    #expect(!TUNHelperLifecyclePolicy.shouldRejectAndExitOnIncomingConnection(binaryMatchesOnDisk: true, hasActiveProcess: true))
    #expect(TUNHelperLifecyclePolicy.shouldRejectAndExitOnIncomingConnection(binaryMatchesOnDisk: false, hasActiveProcess: false))
    #expect(!TUNHelperLifecyclePolicy.shouldRejectAndExitOnIncomingConnection(binaryMatchesOnDisk: false, hasActiveProcess: true))

    #expect(TUNHelperLifecyclePolicy.idleExitDelay(binaryMatchesOnDisk: false, uptimeSeconds: 0) == 0)
    #expect(TUNHelperLifecyclePolicy.idleExitDelay(binaryMatchesOnDisk: false, uptimeSeconds: 100) == 0)
    #expect(
        TUNHelperLifecyclePolicy.idleExitDelay(
            binaryMatchesOnDisk: true,
            uptimeSeconds: 1,
            minimumRuntimeSeconds: 12,
            idleGraceSeconds: 3
        ) == 11
    )
    #expect(
        TUNHelperLifecyclePolicy.idleExitDelay(
            binaryMatchesOnDisk: true,
            uptimeSeconds: 10,
            minimumRuntimeSeconds: 12,
            idleGraceSeconds: 15
        ) == 15
    )
}

private final class FakeTUNDaemonManager: TUNDaemonManaging, @unchecked Sendable {
    private let lock = NSLock()
    var statusValue: TUNDaemonStatus = .enabled
    var registerOutcomeStatus: TUNDaemonStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openApprovalSettingsCount = 0

    func status() -> TUNDaemonStatus {
        lock.withLock { statusValue }
    }

    func register() throws {
        try lock.withLock {
            registerCount += 1
            if let outcome = registerOutcomeStatus {
                statusValue = outcome
            }
            if let registerError {
                throw registerError
            }
        }
    }

    func unregister() async throws {
        try lock.withLock {
            unregisterCount += 1
            if let unregisterError {
                throw unregisterError
            }
        }
    }

    @MainActor func openApprovalSettings() {
        lock.withLock { openApprovalSettingsCount += 1 }
    }
}

private final class FakeTUNHelperSession: TUNHelperSession, @unchecked Sendable {
    private let lock = NSLock()
    private let startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var invalidateCount = 0

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start(configuration: Data) async throws {
        try lock.withLock {
            startCount += 1
            if let startError {
                throw startError
            }
        }
    }

    func stop() async {
        lock.withLock { stopCount += 1 }
    }

    func status() async throws -> TUNHealth {
        TUNHealth(running: true, output: "")
    }

    func invalidate() {
        lock.withLock { invalidateCount += 1 }
    }
}

@MainActor
@Test func privilegedTUNRecoversOnRetryAfterSingleXPCInterruption() async throws {
    let daemon = FakeTUNDaemonManager()
    let session1 = FakeTUNHelperSession(
        startError: NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInterrupted)
    )
    let session2 = FakeTUNHelperSession()
    var createdSessions = 0
    let service = PrivilegedTUNService(
        daemon: daemon,
        requirementProvider: { "anchor apple generic" },
        sessionFactory: { _ in
            createdSessions += 1
            return createdSessions == 1 ? session1 : session2
        },
        retryDelay: .milliseconds(5),
        reregisterDelay: .milliseconds(5)
    )

    try await service.start(configuration: Data("ok".utf8))
    defer { service.invalidate() }

    #expect(service.isRunning)
    #expect(createdSessions == 2)
    #expect(session1.invalidateCount >= 1)
    #expect(session2.startCount == 1)
    #expect(daemon.unregisterCount == 0)
    #expect(daemon.registerCount == 0)
}

@MainActor
@Test func privilegedTUNReregistersDaemonAfterTwoConsecutiveXPCFailures() async throws {
    let daemon = FakeTUNDaemonManager()
    let session1 = FakeTUNHelperSession(
        startError: NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInterrupted)
    )
    let session2 = FakeTUNHelperSession(
        startError: NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)
    )
    let session3 = FakeTUNHelperSession()
    var createdSessions = 0
    let service = PrivilegedTUNService(
        daemon: daemon,
        requirementProvider: { "anchor apple generic" },
        sessionFactory: { _ in
            createdSessions += 1
            switch createdSessions {
            case 1: return session1
            case 2: return session2
            default: return session3
            }
        },
        retryDelay: .milliseconds(5),
        reregisterDelay: .milliseconds(5)
    )

    try await service.start(configuration: Data("ok".utf8))
    defer { service.invalidate() }

    #expect(service.isRunning)
    #expect(createdSessions == 3)
    #expect(daemon.unregisterCount == 1)
    #expect(daemon.registerCount == 1)
    #expect(session3.startCount == 1)
}

@MainActor
@Test func privilegedTUNPromptsForApprovalIfReregistrationRequiresApproval() async {
    let daemon = FakeTUNDaemonManager()
    daemon.registerOutcomeStatus = .requiresApproval
    var createdSessions = 0
    let service = PrivilegedTUNService(
        daemon: daemon,
        requirementProvider: { "anchor apple generic" },
        sessionFactory: { _ in
            createdSessions += 1
            return FakeTUNHelperSession(
                startError: NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)
            )
        },
        retryDelay: .milliseconds(5),
        reregisterDelay: .milliseconds(5)
    )

    do {
        try await service.start(configuration: Data("ok".utf8))
        Issue.record("Expected approval error when re-registration requires user approval.")
    } catch {
        #expect(error.localizedDescription.contains("Login Items & Extensions"))
    }

    #expect(!service.isRunning)
    #expect(createdSessions == 2)
    #expect(daemon.unregisterCount == 1)
    #expect(daemon.registerCount == 1)
    #expect(daemon.openApprovalSettingsCount == 1)
}

@MainActor
@Test func privilegedTUNSurfacesUpgradeGuidanceWhenAllRetriesFail() async {
    let daemon = FakeTUNDaemonManager()
    var createdSessions = 0
    let service = PrivilegedTUNService(
        daemon: daemon,
        requirementProvider: { "anchor apple generic" },
        sessionFactory: { _ in
            createdSessions += 1
            return FakeTUNHelperSession(
                startError: NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInterrupted)
            )
        },
        retryDelay: .milliseconds(5),
        reregisterDelay: .milliseconds(5)
    )

    do {
        try await service.start(configuration: Data("ok".utf8))
        Issue.record("Expected stale helper recovery message when all attempts fail.")
    } catch {
        #expect(error.localizedDescription == PrivilegedTUNService.staleHelperRecoveryMessage)
    }

    #expect(!service.isRunning)
    #expect(createdSessions == 3)
    #expect(daemon.unregisterCount == 1)
    #expect(daemon.registerCount == 1)
}

@MainActor
@Test func privilegedTUNDoesNotRetryOrReregisterOnNonXPCErrors() async {
    let daemon = FakeTUNDaemonManager()
    var createdSessions = 0
    let service = PrivilegedTUNService(
        daemon: daemon,
        requirementProvider: { "anchor apple generic" },
        sessionFactory: { _ in
            createdSessions += 1
            return FakeTUNHelperSession(startError: TUNServiceError("fixture: bad payload"))
        },
        retryDelay: .milliseconds(5),
        reregisterDelay: .milliseconds(5)
    )

    do {
        try await service.start(configuration: Data("ok".utf8))
        Issue.record("Expected direct failure without retries.")
    } catch {
        #expect(error.localizedDescription == "fixture: bad payload")
    }

    #expect(!service.isRunning)
    #expect(createdSessions == 1)
    #expect(daemon.unregisterCount == 0)
    #expect(daemon.registerCount == 0)
}
