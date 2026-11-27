import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@Test func proxyReceiptRecognizesItsLiveOwnerWithoutConfusingAReusedPID() {
    let proxy = SystemProxySnapshot.enabled(host: "127.0.0.1", httpPort: 7890, socksPort: 7890)
    let state = SystemProxyRecoveryState.ownedByCurrentProcess(service: "Wi-Fi", snapshot: proxy, managedProxy: proxy)
    #expect(state.isOwnedByRunningProcess)
    let reusedPID = SystemProxyRecoveryState(
        service: state.service, snapshot: state.snapshot, managedProxy: proxy,
        ownerPID: state.ownerPID, ownerExecutablePath: "/a/different/application"
    )
    #expect(!reusedPID.isOwnedByRunningProcess)
}

@Test func legacyProxyReceiptStillDecodesWithoutOwnershipMetadata() throws {
    let data = Data(#"{"service":"Wi-Fi","snapshot":{"web":{"enabled":false,"host":"","port":0},"secureWeb":{"enabled":false,"host":"","port":0},"socks":{"enabled":false,"host":"","port":0}}}"#.utf8)
    let state = try JSONDecoder().decode(SystemProxyRecoveryState.self, from: data)
    #expect(state.managedProxy == nil)
    #expect(!state.isOwnedByRunningProcess)
}

@Test func restoringAProxyDoesNotOverwriteProtocolsTakenOverByAnotherApp() throws {
    let previous = SystemProxySettings(enabled: false, host: "", port: 0)
    let ours = SystemProxySettings(enabled: true, host: "127.0.0.1", port: 7890)
    let other = SystemProxySettings(enabled: true, host: "127.0.0.1", port: 8888)
    let current = SystemProxySnapshot(web: other, secureWeb: ours, socks: other)
    let restored = SystemProxySnapshot(web: other, secureWeb: previous, socks: other)
    let captureCount = Mutex(0)
    let recorder = ProxyRecoveryRecorder()
    let service = SystemProxyService(
        capture: { _ in
            captureCount.withLock { count in
                count += 1
                return count == 1 ? current : restored
            }
        },
        apply: { command in recorder.commands.withLock { $0.append(contentsOf: command.steps.map(\.arguments)) } }
    )

    try service.restore(
        service: "Wi-Fi", snapshot: .init(web: previous, secureWeb: previous, socks: previous),
        ownedSnapshot: .init(web: ours, secureWeb: ours, socks: ours)
    )

    #expect(recorder.commands.withLock { $0 } == [["-setsecurewebproxystate", "Wi-Fi", "off"]])
}

@Test func removingNexorasProxyPreservesUnrelatedEndpoints() {
    let snapshot = SystemProxySnapshot(
        web: .init(enabled: true, host: "localhost", port: 7891),
        secureWeb: .init(enabled: true, host: "company-proxy", port: 7891),
        socks: .init(enabled: true, host: "127.0.0.1", port: 1080)
    )
    let restored = snapshot.removingProxy(host: "127.0.0.1", httpPort: 7891, socksPort: 7891)

    #expect(!restored.web.enabled)
    #expect(restored.secureWeb == snapshot.secureWeb)
    #expect(restored.socks == snapshot.socks)
}

@Test func restoringProxyRequiresReadbackOfEveryProtocol() {
    let service = SystemProxyService(
        capture: { _ in
            SystemProxySnapshot(
                web: .init(enabled: false, host: "127.0.0.1", port: 7891),
                secureWeb: .init(enabled: true, host: "127.0.0.1", port: 7891),
                socks: .init(enabled: false, host: "127.0.0.1", port: 7891)
            )
        },
        apply: { _ in }
    )
    let disabled = SystemProxySettings(enabled: false, host: "", port: 0)

    #expect(throws: SystemProxyError.restorationNotVerified("Wi-Fi")) {
        try service.restore(service: "Wi-Fi", snapshot: .init(web: disabled, secureWeb: disabled, socks: disabled))
    }
}

@Test func restoringDisabledProxyAcceptsInactiveCachedEndpoints() throws {
    let disabled = SystemProxySettings(enabled: false, host: "", port: 0)
    let cached = SystemProxySettings(enabled: false, host: "127.0.0.1", port: 7891)
    let service = SystemProxyService(
        capture: { _ in .init(web: cached, secureWeb: cached, socks: cached) },
        apply: { _ in }
    )

    try service.restore(service: "Wi-Fi", snapshot: .init(web: disabled, secureWeb: disabled, socks: disabled))
}

@Test func untouchedSystemProxySnapshotCanBeRestoredWithoutAnInvalidEndpoint() throws {
    let untouched = try SystemProxySettings.parse(networksetupOutput: """
    Enabled: No
    Server:
    Port: 0
    Authenticated Proxy Enabled: 0
    """)
    let snapshot = SystemProxySnapshot(web: untouched, secureWeb: untouched, socks: untouched)
    let recorder = ProxyRecoveryRecorder()
    let service = SystemProxyService(run: { executable, arguments in
        #expect(executable == "/usr/sbin/networksetup")
        recorder.commands.withLock { $0.append(arguments) }
        if arguments.last == "0" { throw SystemProxyError.commandFailed(arguments) }
        return ""
    })

    try service.apply(.restore(service: "Fixture Ethernet", snapshot: snapshot))

    #expect(recorder.commands.withLock { $0 } == [
        ["-setwebproxystate", "Fixture Ethernet", "off"],
        ["-setsecurewebproxystate", "Fixture Ethernet", "off"],
        ["-setsocksfirewallproxystate", "Fixture Ethernet", "off"],
    ])
}

@Test func restoringDisabledProxiesNeverActivatesCachedServersAndAttemptsEveryProtocol() throws {
    let disabled = SystemProxySettings(enabled: false, host: "previous-proxy", port: 8080)
    let snapshot = SystemProxySnapshot(web: disabled, secureWeb: disabled, socks: disabled)
    let recorder = ProxyRecoveryRecorder()
    let service = SystemProxyService(run: { _, arguments in
        recorder.commands.withLock { $0.append(arguments) }
        if arguments.first == "-setwebproxystate" { throw SystemProxyError.commandFailed(arguments) }
        return ""
    })

    #expect(throws: SystemProxyError.commandFailed(["-setwebproxystate", "Wi-Fi", "off"])) {
        try service.apply(.restore(service: "Wi-Fi", snapshot: snapshot))
    }

    #expect(recorder.commands.withLock { $0 } == [
        ["-setwebproxystate", "Wi-Fi", "off"],
        ["-setsecurewebproxystate", "Wi-Fi", "off"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
    ])
}

@Test func disablingProxyAttemptsEveryProtocolAndReportsTheFirstFailure() {
    let recorder = ProxyRecoveryRecorder()
    let service = SystemProxyService(run: { _, arguments in
        recorder.commands.withLock { $0.append(arguments) }
        throw SystemProxyError.commandFailed(arguments)
    })

    #expect(throws: SystemProxyError.commandFailed(["-setwebproxystate", "Wi-Fi", "off"])) {
        try service.apply(.disable(service: "Wi-Fi"))
    }

    #expect(recorder.commands.withLock { $0.count } == 3)
}

@Test func enablingProxyStopsOnFailureSoItsOwnerCanRollBack() {
    let recorder = ProxyRecoveryRecorder()
    let service = SystemProxyService(run: { _, arguments in
        recorder.commands.withLock { $0.append(arguments) }
        throw SystemProxyError.commandFailed(arguments)
    })

    #expect(throws: SystemProxyError.commandFailed(["-setwebproxy", "Wi-Fi", "127.0.0.1", "7890"])) {
        try service.apply(.enable(service: "Wi-Fi", host: "127.0.0.1", httpPort: 7890, socksPort: 7891))
    }

    #expect(recorder.commands.withLock { $0.count } == 1)
}

private final class ProxyRecoveryRecorder: Sendable {
    let commands = Mutex<[[String]]>([])
}
