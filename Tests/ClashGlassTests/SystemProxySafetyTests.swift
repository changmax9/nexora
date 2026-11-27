import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@MainActor
@Test func aSecondStoreCannotStopTheRecordedLiveOwnersConnection() async throws {
    let fixture = try SystemProxySafetyFixture()
    defer { fixture.cleanup() }
    let repository = SystemProxyRecoveryRepository(rootURL: fixture.directory.appendingPathComponent("Profiles"))
    let state = SystemProxyRecoveryState.ownedByCurrentProcess(
        service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot,
        managedProxy: .enabled(host: "127.0.0.1", httpPort: 7890, socksPort: 7891)
    )
    try repository.save(state)

    fixture.store.recoverSystemProxyAfterRelaunch()
    await #expect(throws: AutomationControlError.self) {
        try await fixture.store.setConnectionEnabledForAutomation(true)
    }

    #expect(fixture.recorder.commands.withLock { $0.isEmpty })
    #expect(fixture.recorder.captureRequests.withLock { $0.isEmpty })
    #expect(try repository.load() == state)
    #expect(fixture.store.shutdownForApplicationTermination())
    #expect(try repository.load() == state)
}

@MainActor
@Test func recoveringAnOldReceiptPreservesAReplacementProxy() async throws {
    let replacement = SystemProxySettings(enabled: true, host: "127.0.0.1", port: 8888)
    let fixture = try SystemProxySafetyFixture(
        capturedSnapshot: .init(web: replacement, secureWeb: replacement, socks: replacement)
    )
    defer { fixture.cleanup() }
    let repository = SystemProxyRecoveryRepository(rootURL: fixture.directory.appendingPathComponent("Profiles"))
    try repository.save(.init(
        service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot,
        managedProxy: .enabled(host: "127.0.0.1", httpPort: 7890, socksPort: 7891)
    ))

    fixture.store.recoverSystemProxyAfterRelaunch()

    #expect(fixture.recorder.commands.withLock { $0.isEmpty })
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == nil)
    #expect(try repository.load() == nil)
}

@MainActor
@Test func relaunchRecoversTheOriginalProxySnapshotBeforeCapturingItsOwnProxy() async throws {
    let fixture = try SystemProxySafetyFixture()
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    let repository = SystemProxyRecoveryRepository(rootURL: fixture.directory.appendingPathComponent("Profiles"))
    #expect(try repository.load()?.snapshot == SystemProxySafetyFixture.snapshot)
    let savedState = try repository.load()
    let state = try #require(savedState)
    // Model a terminated owner while keeping the recorded proxy endpoints.
    try repository.save(.init(service: state.service, snapshot: state.snapshot, managedProxy: state.managedProxy))
    let recorder = fixture.recorder
    let originalSnapshot = SystemProxySafetyFixture.snapshot
    let relaunched = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: nil, privilegedTUN: nil),
        systemProxyService: SystemProxyService(
            capture: { _ in originalSnapshot },
            apply: { command in recorder.commands.withLock { $0.append(command) } }
        ),
        profileRepository: ManagedProfileRepository(rootURL: fixture.directory.appendingPathComponent("Profiles")),
        userDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
        automaticallyMonitorsRuntime: false
    )

    relaunched.recoverSystemProxyAfterRelaunch()

    #expect(fixture.recorder.commands.withLock { $0.last } == .restore(
        service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot
    ))
    #expect(!relaunched.isSystemProxyEnabled)
    #expect(relaunched.systemProxyErrorMessage == nil)
    #expect(try repository.load() == nil)
}

@MainActor
@Test func relaunchRestoresAnIndependentProxyEvenWhenItUsesTheAppsDefaultPort() throws {
    let owned = SystemProxySnapshot.enabled(host: "127.0.0.1", httpPort: 43111, socksPort: 43111)
    let original = SystemProxySnapshot.enabled(host: "127.0.0.1", httpPort: 7890, socksPort: 7890)
    let fixture = try SystemProxySafetyFixture(capturedSnapshot: owned, restoredSnapshot: original)
    defer { fixture.cleanup() }
    let repository = SystemProxyRecoveryRepository(rootURL: fixture.directory.appendingPathComponent("Profiles"))
    try repository.save(.init(service: "Wi-Fi", snapshot: original, managedProxy: owned))

    fixture.store.recoverSystemProxyAfterRelaunch()

    #expect(fixture.recorder.commands.withLock { $0.last } == .restore(service: "Wi-Fi", snapshot: original))
    #expect(try repository.load() == nil)
}

@MainActor
@Test func failedProxyRestoreRetainsItsDurableRecoverySnapshot() async throws {
    let fixture = try SystemProxySafetyFixture(restoreFailuresRemaining: 1)
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    await fixture.store.applySystemProxy(enabled: false)
    let repository = SystemProxyRecoveryRepository(rootURL: fixture.directory.appendingPathComponent("Profiles"))

    #expect(try repository.load()?.service == "Fixture Ethernet")
    #expect(try repository.load()?.snapshot == SystemProxySafetyFixture.snapshot)

    await fixture.store.applySystemProxy(enabled: false)

    #expect(try repository.load() == nil)
}

@MainActor
@Test func failureToSaveRecoverySettingsDoesNotChangeSystemProxies() async throws {
    let fixture = try SystemProxySafetyFixture()
    defer { fixture.cleanup() }
    try Data().write(to: fixture.directory.appendingPathComponent("Profiles"))

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")

    #expect(fixture.recorder.commands.withLock { $0.isEmpty })
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage != nil)
}

@MainActor
@Test func disconnectDoesNotRestoreNexorasOwnProxyToAStoppedListener() async throws {
    let enabled = SystemProxySettings(enabled: true, host: "127.0.0.1", port: 7891)
    let disabled = SystemProxySettings(enabled: false, host: "127.0.0.1", port: 7891)
    let fixture = try SystemProxySafetyFixture(
        capturedSnapshot: .init(web: enabled, secureWeb: enabled, socks: enabled),
        restoredSnapshot: .init(web: disabled, secureWeb: disabled, socks: disabled)
    )
    defer { fixture.cleanup() }
    fixture.store.httpPort = 7891
    fixture.store.socksPort = 7891

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    await fixture.store.applySystemProxy(enabled: false)

    #expect(fixture.recorder.commands.withLock { $0.last } == .restore(
        service: "Fixture Ethernet",
        snapshot: .init(web: disabled, secureWeb: disabled, socks: disabled)
    ))
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == nil)
}

@MainActor
@Test func failedProxySnapshotCaptureDoesNotChangeSystemSettings() async throws {
    let fixture = try SystemProxySafetyFixture(captureFails: true)
    defer { fixture.cleanup() }

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    await fixture.store.applySystemProxy(enabled: false, service: "Fixture Ethernet")

    #expect(fixture.recorder.captureRequests.withLock { $0 } == ["Fixture Ethernet"])
    #expect(fixture.recorder.commands.withLock { $0.isEmpty })
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.lastErrorMessage == "fixture: proxy capture unavailable")
}

@MainActor
@Test func proxyRestoreUsesTheServiceWhoseSettingsWereCaptured() async throws {
    let fixture = try SystemProxySafetyFixture()
    defer { fixture.cleanup() }
    fixture.store.networkService = "Wi-Fi"

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    fixture.store.networkService = "Renamed Wi-Fi"
    await fixture.store.applySystemProxy(enabled: false)

    #expect(fixture.recorder.captureRequests.withLock { $0 } == Array(repeating: "Fixture Ethernet", count: 3))
    #expect(fixture.recorder.commands.withLock { $0 } == [
        .enable(service: "Fixture Ethernet", host: "127.0.0.1", httpPort: 7890, socksPort: 7891),
        .restore(service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot),
    ])
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.lastErrorMessage == nil)
}

@MainActor
@Test func partiallyFailedProxyEnableRestoresTheCapturedSettings() async throws {
    let fixture = try SystemProxySafetyFixture(enableFails: true)
    defer { fixture.cleanup() }

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")

    #expect(fixture.recorder.commands.withLock { $0 } == [
        .enable(service: "Fixture Ethernet", host: "127.0.0.1", httpPort: 7890, socksPort: 7891),
        .restore(service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot),
    ])
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.lastErrorMessage == "fixture: proxy enable failed")
}

@MainActor
@Test func failedProxyRestoreRemainsVisibleAfterSuccessfulTrafficUpdates() async throws {
    let fixture = try SystemProxySafetyFixture(restoreFailuresRemaining: 1)
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")

    await fixture.store.applySystemProxy(enabled: false)
    fixture.store.lastErrorMessage = nil
    fixture.store.applyTrafficResponse(Data(#"{"up":1024,"down":2048}"#.utf8))

    #expect(fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == "fixture: proxy restore failed")
    #expect(fixture.store.lastErrorMessage == "fixture: proxy restore failed")
    #expect(fixture.store.speedSamples.last != 0)
}

@MainActor
@Test func dismissingProxyFailureAlertKeepsRecoveryStateWithoutRepeatingTheAlert() async throws {
    let fixture = try SystemProxySafetyFixture(restoreFailuresRemaining: 1)
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    await fixture.store.applySystemProxy(enabled: false)
    try #require(fixture.store.errorAlertMessage == "fixture: proxy restore failed")

    fixture.store.dismissErrorAlert()

    #expect(fixture.store.errorAlertMessage == nil)
    #expect(fixture.store.systemProxyErrorMessage == "fixture: proxy restore failed")
    #expect(fixture.store.lastErrorMessage == "fixture: proxy restore failed")
    #expect(fixture.store.isSystemProxyEnabled)

    fixture.store.applyTrafficResponse(Data(#"{"up":1024,"down":2048}"#.utf8))

    #expect(fixture.store.errorAlertMessage == nil)
    #expect(fixture.store.systemProxyErrorMessage == "fixture: proxy restore failed")
    #expect(fixture.store.lastErrorMessage == "fixture: proxy restore failed")

    await fixture.store.applySystemProxy(enabled: false)

    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == nil)
    #expect(fixture.store.lastErrorMessage == nil)
    #expect(fixture.store.errorAlertMessage == nil)
}

@MainActor
@Test func retryingFailedProxyRestoreKeepsTheOriginalSnapshotAndClearsItsError() async throws {
    let fixture = try SystemProxySafetyFixture(restoreFailuresRemaining: 1)
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")
    await fixture.store.applySystemProxy(enabled: false)
    try #require(fixture.store.isSystemProxyEnabled)
    try #require(fixture.store.systemProxyErrorMessage != nil)

    fixture.store.networkService = "Renamed Wi-Fi"
    await fixture.store.applySystemProxy(enabled: false)

    #expect(fixture.recorder.captureRequests.withLock { $0 } == Array(repeating: "Fixture Ethernet", count: 4))
    #expect(fixture.recorder.commands.withLock { $0 } == [
        .enable(service: "Fixture Ethernet", host: "127.0.0.1", httpPort: 7890, socksPort: 7891),
        .restore(service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot),
        .restore(service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot),
    ])
    #expect(!fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == nil)
    #expect(fixture.store.lastErrorMessage == nil)
}

@MainActor
@Test func changingProxyServiceRestoresTheOldServiceBeforeCapturingTheNewOne() async throws {
    let fixture = try SystemProxySafetyFixture()
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Wi-Fi")

    #expect(fixture.recorder.events.withLock { $0 } == [
        .capture("Fixture Ethernet"),
        .apply(.enable(service: "Fixture Ethernet", host: "127.0.0.1", httpPort: 7890, socksPort: 7891)),
        .capture("Fixture Ethernet"),
        .apply(.restore(service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot)),
        .capture("Fixture Ethernet"),
        .capture("Fixture Wi-Fi"),
        .apply(.enable(service: "Fixture Wi-Fi", host: "127.0.0.1", httpPort: 7890, socksPort: 7891)),
    ])
    #expect(fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == nil)

    await fixture.store.applySystemProxy(enabled: false)
    #expect(fixture.recorder.commands.withLock { $0.last } ==
        .restore(service: "Fixture Wi-Fi", snapshot: SystemProxySafetyFixture.snapshot))
}

@MainActor
@Test func failedOldServiceRestorePreventsChangingAnotherServicesProxy() async throws {
    let fixture = try SystemProxySafetyFixture(restoreFailuresRemaining: 1)
    defer { fixture.cleanup() }
    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Ethernet")

    await fixture.store.applySystemProxy(enabled: true, service: "Fixture Wi-Fi")

    #expect(fixture.recorder.events.withLock { $0 } == [
        .capture("Fixture Ethernet"),
        .apply(.enable(service: "Fixture Ethernet", host: "127.0.0.1", httpPort: 7890, socksPort: 7891)),
        .capture("Fixture Ethernet"),
        .apply(.restore(service: "Fixture Ethernet", snapshot: SystemProxySafetyFixture.snapshot)),
    ])
    #expect(fixture.store.isSystemProxyEnabled)
    #expect(fixture.store.systemProxyErrorMessage == "fixture: proxy restore failed")
}

private enum ProxySafetyFailure: LocalizedError {
    case capture
    case enable
    case restore

    var errorDescription: String? {
        switch self {
        case .capture: "fixture: proxy capture unavailable"
        case .enable: "fixture: proxy enable failed"
        case .restore: "fixture: proxy restore failed"
        }
    }
}

private enum ProxySafetyEvent: Equatable, Sendable {
    case capture(String)
    case apply(SystemProxyCommand)
}

private final class ProxySafetyRecorder: Sendable {
    let captureRequests = Mutex<[String]>([])
    let commands = Mutex<[SystemProxyCommand]>([])
    let events = Mutex<[ProxySafetyEvent]>([])
    let restoreFailuresRemaining = Mutex<Int>(0)
}

@MainActor
private final class SystemProxySafetyFixture {
    static let snapshot = SystemProxySnapshot(
        web: .init(enabled: true, host: "previous-http", port: 8123),
        secureWeb: .init(enabled: false, host: "previous-https", port: 8124),
        socks: .init(enabled: false, host: "previous-socks", port: 8125)
    )

    let directory: URL
    let recorder = ProxySafetyRecorder()
    let store: AppStore
    private let defaults: UserDefaults
    private let identifier: String

    init(
        captureFails: Bool = false,
        enableFails: Bool = false,
        restoreFailuresRemaining: Int = 0,
        capturedSnapshot: SystemProxySnapshot = SystemProxySafetyFixture.snapshot,
        restoredSnapshot: SystemProxySnapshot? = nil
    ) throws {
        identifier = "NexoraProxySafety-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: identifier))
        let recorder = recorder
        recorder.restoreFailuresRemaining.withLock { $0 = restoreFailuresRemaining }
        let restored = Mutex(false)
        store = AppStore(
            coreService: MihomoCoreService(coreBinaryURL: nil, privilegedTUN: nil),
            systemProxyService: SystemProxyService(
                capture: { service in
                    recorder.captureRequests.withLock { $0.append(service) }
                    recorder.events.withLock { $0.append(.capture(service)) }
                    if captureFails { throw ProxySafetyFailure.capture }
                    return restored.withLock { $0 } ? (restoredSnapshot ?? capturedSnapshot) : capturedSnapshot
                },
                apply: { command in
                    recorder.commands.withLock { $0.append(command) }
                    recorder.events.withLock { $0.append(.apply(command)) }
                    if enableFails, command.steps.count == 3 { throw ProxySafetyFailure.enable }
                    if command.continuesAfterFailure,
                       recorder.restoreFailuresRemaining.withLock({ remaining in
                           guard remaining > 0 else { return false }
                           remaining -= 1
                           return true
                       }) {
                        throw ProxySafetyFailure.restore
                    }
                    if command.continuesAfterFailure { restored.withLock { $0 = true } }
                }
            ),
            profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Profiles")),
            userDefaults: defaults,
            automaticallyMonitorsRuntime: false
        )
    }

    func cleanup() {
        store.shutdownForApplicationTermination()
        defaults.removePersistentDomain(forName: identifier)
        try? FileManager.default.removeItem(at: directory)
    }
}
