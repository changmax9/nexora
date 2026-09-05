import Darwin
import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@Suite(.serialized)
@MainActor
struct RuntimeLifecycleRegressionTests {
    @Test func outboundModeSurvivesPauseAndUnexpectedExit() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startVPN()
        await fixture.store.setOutboundMode(.global)
        #expect(fixture.store.selectedMode == .global)
        await fixture.store.toggleRuntime(configPath: fixture.store.configPath)
        try await fixture.startVPN()
        #expect(fixture.store.selectedMode == .global)

        #expect(Darwin.kill(try fixture.corePID(), SIGKILL) == 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while fixture.store.isCoreRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await fixture.startVPN()
        #expect(fixture.store.selectedMode == .global)
    }

    @Test func acceptedNodeChangeSurvivesFailureToCloseOldConnections() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        fixture.controller.state.withLock {
            $0.selectedProxy = "Alpha"
            $0.rejectCloseConnections = true
        }
        try await fixture.startController()
        await fixture.store.selectProxyRemote(groupName: "Routes", nodeName: "Beta")
        #expect(fixture.controller.state.withLock { $0.selectedProxy } == "Beta")
        #expect(fixture.store.menuBarSelectedNodeName == "Beta")
        #expect(fixture.store.lastErrorMessage?.contains("Close rejected") == true)
    }

    @Test func importingWhileConnectedAppliesTheSelectedProfile() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startVPN()
        let previousPID = try fixture.corePID()

        await fixture.store.importManagedProfile(from: fixture.sourceB)

        #expect(fixture.store.selectedProfile == "B")
        #expect(fixture.store.selectedManagedProfileID != fixture.profileA.id)
        try fixture.expectRuntimeMatchesSelectedProfile(mode: .direct, port: 42790)
        #expect(try fixture.corePID() != previousPID)
        #expect(fixture.store.isStarted)
        #expect(fixture.store.lastErrorMessage == nil)
        #expect(fixture.proxyCommands.last == .enable(
            service: "Wi-Fi", host: "127.0.0.1", httpPort: 42790, socksPort: 42790
        ))
    }

    @Test func deletingCurrentProfileSwitchesTheRunningCoreToItsReplacement() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startVPN()
        let previousPID = try fixture.corePID()

        await fixture.store.removeManagedProfile(fixture.profileA.id)

        #expect(fixture.store.selectedManagedProfileID == fixture.profileB.id)
        #expect(!FileManager.default.fileExists(atPath: fixture.profileA.managedConfigURL.path))
        #expect(try fixture.corePID() != previousPID)
        try fixture.expectRuntimeMatchesSelectedProfile(mode: .direct, port: 42790)
        #expect(fixture.store.isStarted)
        #expect(fixture.store.lastErrorMessage == nil)
    }

    @Test func deletingAnInactiveProfileKeepsAllocatedRuntimePorts() async throws {
        let fixture = try await RuntimeLifecycleFixture.make(occupyPreferredPorts: true)
        defer { fixture.cleanup() }
        try await fixture.startController()
        let previousPID = try fixture.corePID()
        let previousConfig = try Data(contentsOf: fixture.repository.runtimeConfigURL)
        let previousController = fixture.store.controllerURL
        #expect(fixture.store.httpPort == 41791)

        await fixture.store.removeManagedProfile(fixture.profileB.id)

        #expect(fixture.store.selectedManagedProfileID == fixture.profileA.id)
        #expect(fixture.store.httpPort == 41791)
        #expect(fixture.store.controllerURL == previousController)
        #expect(try fixture.corePID() == previousPID)
        #expect(try Data(contentsOf: fixture.repository.runtimeConfigURL) == previousConfig)
        #expect(!fixture.store.isStarted)
    }

    @Test func deletingTheLastProfileStopsAndRemovesItsRuntimeConfiguration() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        await fixture.store.removeManagedProfile(fixture.profileB.id)
        try await fixture.startVPN()

        await fixture.store.removeManagedProfile(fixture.profileA.id)

        #expect(fixture.store.managedProfiles.isEmpty)
        #expect(fixture.store.selectedManagedProfileID == nil)
        #expect(!fixture.store.isStarted)
        #expect(!fixture.core.isProcessRunning)
        #expect(!fixture.store.isSystemProxyEnabled)
        #expect(!FileManager.default.fileExists(atPath: fixture.repository.runtimeConfigURL.path))
        #expect(fixture.proxyCommands.last == .restore(
            service: "Wi-Fi", snapshot: RuntimeLifecycleFixture.previousProxy
        ))
        await fixture.store.refreshProxies()
        #expect(!fixture.core.isProcessRunning)
        #expect(fixture.store.lastErrorMessage != nil)
    }

    @Test func failedProfileSwitchPreservesTheStartupError() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startVPN()
        try fixture.rejectStartup()

        await fixture.store.selectManagedProfile(fixture.profileB.id)

        #expect(!fixture.store.isStarted)
        #expect(!fixture.core.isProcessRunning)
        #expect(!fixture.store.isSystemProxyEnabled)
        #expect(fixture.store.coreStatus.failureMessage == "fixture: selected profile cannot start")
        #expect(fixture.store.lastErrorMessage == "fixture: selected profile cannot start")
        #expect(!fixture.store.isRuntimeTransitioning)
    }

    @Test func failedReplacementDoesNotDeleteTheOriginalProfile() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startController()
        try fixture.rejectStartup()

        await fixture.store.removeManagedProfile(fixture.profileA.id)

        #expect(FileManager.default.fileExists(atPath: fixture.profileA.managedConfigURL.path))
        #expect(fixture.store.managedProfiles.count == 2)
        #expect(fixture.store.lastErrorMessage == "fixture: selected profile cannot start")
        #expect(!fixture.store.isStarted)
    }

    @Test func concurrentImportsAreQueuedWithoutDroppingFiles() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        let first = Task { await fixture.store.importManagedProfile(from: fixture.sourceB) }
        let second = Task { await fixture.store.importManagedProfile(from: fixture.sourceB) }
        await first.value
        await second.value

        #expect(fixture.store.managedProfiles.count == 4)
        #expect(try fixture.repository.loadProfiles().count == 4)
        #expect(!fixture.store.isRuntimeTransitioning)
        #expect(fixture.store.lastErrorMessage == nil)
    }

    @Test func tunChoiceSurvivesControllerPreparationAndAppliesOnVPNStart() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        await fixture.store.setTunEnabled(true)

        try await fixture.startController()
        await fixture.store.refreshRuntimeConfiguration()

        #expect(fixture.store.isTunEnabled)
        #expect(fixture.store.stagedTunEnabled == true)
        #expect(!fixture.controller.tunEnabled())
        try await fixture.startVPN()
        #expect(fixture.store.isTunEnabled)
        #expect(fixture.store.stagedTunEnabled == nil)
        #expect(fixture.controller.tunEnabled())
        #expect(fixture.controller.tunPatches() == [true])
        #expect(try MihomoConfigurationInspector.inspect(url: fixture.profileA.managedConfigURL).tunEnabled == false)
    }

    @Test func controllerOnlyTunChoiceIsPreservedUntilVPNStarts() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startController()

        await fixture.store.setTunEnabled(true)
        await fixture.store.refreshRuntimeConfiguration()

        #expect(fixture.store.isTunEnabled)
        #expect(fixture.store.stagedTunEnabled == true)
        #expect(fixture.controller.tunPatches().isEmpty)
        try await fixture.startVPN()
        #expect(fixture.controller.tunEnabled())
        #expect(fixture.store.stagedTunEnabled == nil)
    }

    @Test func activeTunFailureRestoresTheConfirmedChoice() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startVPN()
        fixture.controller.state.withLock { $0.rejectTun = true }

        await fixture.store.setTunEnabled(true)

        #expect(!fixture.store.isTunEnabled)
        #expect(!fixture.controller.tunEnabled())
        #expect(fixture.store.lastErrorMessage != nil)
        #expect(!fixture.store.isRuntimeTransitioning)
    }

    @Test func unconfirmedTunChangePreventsVPNActivationAndCanBeRetried() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        await fixture.store.setTunEnabled(true)
        fixture.controller.state.withLock { $0.ignoreTun = true }

        await fixture.store.toggleRuntime(configPath: fixture.store.configPath)

        #expect(!fixture.store.isStarted)
        #expect(fixture.store.stagedTunEnabled == true)
        #expect(fixture.store.lastErrorMessage == "Mihomo did not enable TUN.")
        #expect(fixture.proxyCommands.isEmpty)

        fixture.controller.state.withLock { $0.ignoreTun = false }
        try await fixture.startVPN()
        #expect(fixture.controller.tunEnabled())
        #expect(fixture.store.lastErrorMessage == nil)
    }

    @Test func tunChoiceSurvivesPauseAndCoreRestart() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        await fixture.store.setTunEnabled(true)
        try await fixture.startVPN()
        await fixture.store.toggleRuntime(configPath: fixture.store.configPath)
        #expect(!fixture.store.isStarted)

        try await fixture.startVPN()
        #expect(fixture.controller.tunEnabled())
        let previousPID = try fixture.corePID()
        await fixture.store.restartCore()

        #expect(fixture.store.isStarted)
        #expect(fixture.store.isTunEnabled)
        #expect(fixture.controller.tunEnabled())
        #expect(try fixture.corePID() != previousPID)
        #expect(fixture.store.lastErrorMessage == nil)
        #expect(!fixture.store.isRuntimeTransitioning)
    }

    @Test func controllerExitUpdatesStatusWithoutAWindowTick() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startController()

        #expect(Darwin.kill(try fixture.corePID(), SIGKILL) == 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while fixture.store.isCoreRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!fixture.core.isProcessRunning)
        #expect(!fixture.store.isCoreRunning)
        #expect(fixture.store.coreStatus.failureMessage != nil)
        #expect(fixture.store.lastErrorMessage != nil)
    }

    @Test func runtimeTickDetectsAStoppedControllerWhileVPNIsOff() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try await fixture.startController()
        fixture.core.stopImmediately()

        await fixture.store.runtimeTick()

        #expect(!fixture.store.isCoreRunning)
        #expect(!fixture.store.isStarted)
        #expect(fixture.store.coreStatus.failureMessage != nil)
    }

    @Test func rapidStartClicksDoNotRepeatAFailedStartup() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        try fixture.rejectStartup()

        let first = Task { await fixture.store.toggleRuntime(configPath: fixture.store.configPath) }
        let second = Task { await fixture.store.toggleRuntime(configPath: fixture.store.configPath) }
        await first.value
        await second.value

        #expect(try fixture.validationCount() == 1)
        #expect(!fixture.store.isRuntimeTransitioning)
        #expect(fixture.store.lastErrorMessage == "fixture: selected profile cannot start")
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("reject"))
        try await fixture.startVPN()
        #expect(try fixture.validationCount() == 2)
    }

    @Test func backgroundRefreshAndStartShareOneControllerLaunch() async throws {
        let fixture = try await RuntimeLifecycleFixture.make()
        defer { fixture.cleanup() }
        let start = Task { await fixture.store.toggleRuntime(configPath: fixture.store.configPath) }
        let refresh = Task { await fixture.store.refreshProxies() }
        await start.value
        await refresh.value

        #expect(fixture.store.isStarted)
        #expect(fixture.core.isProcessRunning)
        #expect(try fixture.validationCount() == 1)
        #expect(!fixture.store.isRuntimeTransitioning)
    }
}

@MainActor
private struct RuntimeLifecycleFixture {
    let directory: URL
    let repository: ManagedProfileRepository
    let profileA: ManagedProfile
    let profileB: ManagedProfile
    let sourceB: URL
    let store: AppStore
    let core: MihomoCoreService
    let controller: RuntimeControllerFixture
    let session: URLSession
    let defaults: UserDefaults
    let identifier: String

    var proxyCommands: [SystemProxyCommand] {
        controller.state.withLock { $0.proxyCommands }
    }

    static let previousProxy = SystemProxySnapshot(
        web: .init(enabled: false, host: "previous-proxy", port: 8888),
        secureWeb: .init(enabled: false, host: "previous-proxy", port: 8888),
        socks: .init(enabled: false, host: "previous-proxy", port: 8888)
    )

    static func make(occupyPreferredPorts: Bool = false) async throws -> RuntimeLifecycleFixture {
        let identifier = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        fixture_dir="$(dirname "$0")"
        if [ "$1" = "-t" ]; then
          echo attempt >> "$fixture_dir/validations"
          if [ -f "$fixture_dir/reject" ]; then
            /bin/sleep 0.2
            echo 'fixture: selected profile cannot start' >&2
            exit 1
          fi
          exit 0
        fi
        exec /bin/sleep 60
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let fakeCurl = directory.appendingPathComponent("fake-curl")
        try """
        #!/bin/sh
        echo '{"success":true,"ip":"192.0.2.10","country_code":"US","country":"Fixture"}'
        """.write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        try Data("fixture".utf8).write(to: directory.appendingPathComponent("geoip.dat"))
        try Data("fixture".utf8).write(to: directory.appendingPathComponent("geosite.dat"))
        let sourceA = directory.appendingPathComponent("A.yaml")
        let sourceB = directory.appendingPathComponent("B.yaml")
        try yaml(mode: "rule", port: 41790, controller: 41990)
            .write(to: sourceA, atomically: true, encoding: .utf8)
        try yaml(mode: "direct", port: 42790, controller: 42990)
            .write(to: sourceB, atomically: true, encoding: .utf8)
        let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
        let profileA = try await repository.importProfile(from: sourceA) { _ in .success }
        let profileB = try await repository.importProfile(from: sourceB) { _ in .success }
        try repository.select(profileA.id)
        let controller = RuntimeControllerFixture(runtimeURL: repository.runtimeConfigURL)
        RuntimeLifecycleURLProtocol.fixtures.withLock { $0[identifier] = controller }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeLifecycleURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Nexora-Test-Fixture": identifier]
        let session = URLSession(configuration: configuration)
        let core = MihomoCoreService(coreBinaryURL: executable)
        let defaults = try #require(UserDefaults(suiteName: identifier))
        let previousProxy = previousProxy
        let store = AppStore(
            coreService: core,
            apiService: MihomoAPIService(
                requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:41990")!),
                session: session
            ),
            systemProxyService: SystemProxyService(
                capture: { _ in previousProxy },
                apply: { command in controller.state.withLock { $0.proxyCommands.append(command) } }
            ),
            profileRepository: repository,
            runtimeConfigurationPreparer: RuntimeConfigurationPreparer(
                geoDataSourceURL: directory,
                portAllocator: RuntimePortAllocator(
                    isTCPPortAvailable: { _, port in
                        !occupyPreferredPorts || ![41790, 41990, 42790, 42990].contains(port)
                    },
                    isUDPPortAvailable: { _, _ in true }
                )
            ),
            networkIdentityService: NetworkIdentityService(
                ipv4Endpoint: URL(string: "fixture-only://identity")!,
                directFetcher: DirectNetworkIdentityFetcher(executableURL: fakeCurl),
                systemTunnelDetector: { false }
            ),
            userDefaults: defaults
        )
        return RuntimeLifecycleFixture(
            directory: directory, repository: repository, profileA: profileA, profileB: profileB,
            sourceB: sourceB, store: store, core: core, controller: controller,
            session: session, defaults: defaults, identifier: identifier
        )
    }

    static func yaml(mode: String, port: Int, controller: Int) -> String {
        """
        mixed-port: \(port)
        external-controller: 127.0.0.1:\(controller)
        mode: \(mode)
        tun:
          enable: false
        proxies: []
        proxy-groups: []
        rules:
          - MATCH,DIRECT
        """
    }

    func startController() async throws {
        await store.refreshProxies()
        try #require(core.isProcessRunning)
        try #require(store.isCoreRunning)
        try #require(!store.isStarted)
        try #require(store.lastErrorMessage == nil)
    }

    func startVPN() async throws {
        await store.toggleRuntime(configPath: store.configPath)
        try #require(store.isStarted, "\(store.lastErrorMessage ?? "VPN did not start")")
        try #require(store.isSystemProxyEnabled)
        try #require(core.isProcessRunning)
        try #require(store.lastErrorMessage == nil)
    }

    func corePID() throws -> pid_t {
        let pidFile = repository.runtimeDirectoryURL.appendingPathComponent("mihomo.pid")
        let pid = try String(contentsOf: pidFile, encoding: .utf8).split(separator: "\n").first
        return try #require(pid.flatMap { pid_t($0) })
    }

    func validationCount() throws -> Int {
        try String(contentsOf: directory.appendingPathComponent("validations"), encoding: .utf8)
            .split(separator: "\n").count
    }

    func rejectStartup() throws {
        try Data().write(to: directory.appendingPathComponent("reject"))
    }

    func expectRuntimeMatchesSelectedProfile(mode: OutboundMode, port: Int) throws {
        let runtime = try MihomoConfigurationInspector.inspect(url: repository.runtimeConfigURL)
        #expect(runtime.mode == mode)
        #expect(runtime.httpPort == port)
        #expect(store.selectedMode == mode)
        #expect(store.httpPort == port)
        #expect(store.controllerURL.port == runtime.controllerPort)
        #expect(core.isProcessRunning)
    }

    func cleanup() {
        store.shutdownForApplicationTermination()
        session.invalidateAndCancel()
        _ = RuntimeLifecycleURLProtocol.fixtures.withLock { $0.removeValue(forKey: identifier) }
        defaults.removePersistentDomain(forName: identifier)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class RuntimeControllerFixture: Sendable {
    struct State: Sendable {
        var proxyCommands: [SystemProxyCommand] = []
        var tunByProcess: [String: Bool] = [:]
        var modeByProcess: [String: String] = [:]
        var tunRequests: [Bool] = []
        var rejectTun = false
        var ignoreTun = false
        var selectedProxy: String?
        var rejectCloseConnections = false
    }

    let state = Mutex(State())
    let runtimeURL: URL

    init(runtimeURL: URL) {
        self.runtimeURL = runtimeURL
    }

    private var processKey: String {
        (try? String(
            contentsOf: runtimeURL.deletingLastPathComponent().appendingPathComponent("mihomo.pid"),
            encoding: .utf8
        )) ?? "stopped"
    }

    func tunEnabled() -> Bool {
        let key = processKey
        return state.withLock { $0.tunByProcess[key] }
            ?? (try? MihomoConfigurationInspector.inspect(url: runtimeURL).tunEnabled) ?? false
    }

    func tunPatches() -> [Bool] {
        state.withLock { $0.tunRequests }
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let body: Data
        if let data = request.httpBody {
            body = data
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        } else {
            body = Data("{}".utf8)
        }
        return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    }

    func response(for request: URLRequest) throws -> (Int, Data) {
        let key = processKey
        let config = try MihomoConfigurationInspector.inspect(url: runtimeURL)
        guard request.url?.port == config.controllerPort, key != "stopped" else {
            return (503, Data(#"{"message":"Controller unavailable"}"#.utf8))
        }
        let path = request.url?.path
        if request.httpMethod == "PUT", path == "/proxies/Routes" {
            let node = try jsonBody(request)["name"] as? String
            state.withLock { $0.selectedProxy = node }
            return (204, Data())
        }
        if request.httpMethod == "DELETE", path == "/connections",
           state.withLock({ $0.rejectCloseConnections }) {
            return (500, Data(#"{"message":"Close rejected"}"#.utf8))
        }
        if request.httpMethod == "PATCH", path == "/configs" {
            let values = try jsonBody(request)
            let tun = (values["tun"] as? [String: Any])?["enable"] as? Bool
            let mode = values["mode"] as? String
            let rejected = state.withLock { state in
                if let tun {
                    state.tunRequests.append(tun)
                    if state.rejectTun { return true }
                    if !state.ignoreTun { state.tunByProcess[key] = tun }
                }
                if let mode { state.modeByProcess[key] = mode }
                return false
            }
            return rejected
                ? (500, Data(#"{"message":"TUN rejected"}"#.utf8))
                : (204, Data())
        }
        let body: [String: Any]
        switch path {
        case "/version":
            body = ["version": "fixture"]
        case "/configs":
            body = [
                "mode": state.withLock { $0.modeByProcess[key] } ?? config.mode.rawValue,
                "mixed-port": config.httpPort,
                "tun": ["enable": tunEnabled()]
            ]
        case "/proxies":
            if let selected = state.withLock({ $0.selectedProxy }) {
                body = ["proxies": [
                    "Routes": ["type": "Selector", "now": selected, "all": ["Alpha", "Beta"]],
                    "Alpha": ["type": "Shadowsocks"], "Beta": ["type": "Shadowsocks"]
                ]]
            } else {
                body = ["proxies": [:]]
            }
        case "/connections":
            body = ["connections": [], "uploadTotal": 0, "downloadTotal": 0]
        default:
            body = [:]
        }
        return (200, try JSONSerialization.data(withJSONObject: body))
    }
}

private final class RuntimeLifecycleURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = Mutex<[String: RuntimeControllerFixture]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let identifier = request.value(forHTTPHeaderField: "X-Nexora-Test-Fixture") ?? ""
            guard let fixture = Self.fixtures.withLock({ $0[identifier] }),
                  let url = request.url else { throw URLError(.resourceUnavailable) }
            let (status, data) = try fixture.response(for: request)
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Leave the traffic stream open until the owning test cancels its session.
            if url.path == "/traffic" { return }
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
