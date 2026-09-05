import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@MainActor
@Test func newerIdentityRefreshWinsAndKeepsTheLastSnapshotWhileLoading() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-curl")
    try """
    #!/bin/sh
    echo '{"success":true,"ip":"203.0.113.42","country_code":"JP","country":"Japan"}'
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let gate = IdentityOrderingGate()
    defer { gate.release.signal() }
    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Profiles")),
        networkIdentityService: NetworkIdentityService(
            directFetcher: DirectNetworkIdentityFetcher(executableURL: executable),
            systemTunnelDetector: { gate.detect() }
        )
    )
    store.externalIP = "198.51.100.1"
    store.networkCountryCode = "US"
    store.networkEgressKind = .direct
    let older = Task { await store.refreshNetworkIdentity() }
    await gate.waitUntilStarted()
    #expect(store.isRefreshingNetworkIdentity)
    #expect(store.externalIP == "198.51.100.1")
    #expect(store.networkCountryCode == "US")

    await store.refreshNetworkIdentity()
    #expect(store.externalIP == "203.0.113.42")
    #expect(store.networkEgressKind == .direct)
    gate.release.signal()
    await older.value
    // The older detector returns a tunnel, but must not overwrite the newer result.
    #expect(store.networkEgressKind == .direct)
    #expect(!store.isRefreshingNetworkIdentity)
}

private final class IdentityOrderingGate: Sendable {
    let calls = Mutex(0)
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = self.started.wait(timeout: .now() + 10)
                continuation.resume()
            }
        }
    }

    func detect() -> Bool {
        let first = calls.withLock { count in
            count += 1
            return count == 1
        }
        guard first else { return false }
        started.signal()
        _ = release.wait(timeout: .now() + 10)
        return true
    }
}
