import Foundation
import Testing
@testable import ClashGlassCore

@Test func proxySelectionRepositoryPersistsPerProfile() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let profileA = UUID()
    let profileB = UUID()
    let repository = ProxySelectionRepository(rootURL: rootURL)

    try repository.save(selector: "Mutdot", node: "日本JP04", profileID: profileA)
    try repository.save(selector: "Mutdot", node: "香港HK04", profileID: profileB)

    #expect(try repository.selections(profileID: profileA) == ["Mutdot": "日本JP04"])
    #expect(try repository.selections(profileID: profileB) == ["Mutdot": "香港HK04"])
}

@Test func runtimeConfigurationPreparerChoosesFreePorts() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("source.yaml")
    let runtimeURL = directory.appendingPathComponent("Runtime", isDirectory: true)
    let geoDataURL = directory.appendingPathComponent("GeoData", isDirectory: true)
    try FileManager.default.createDirectory(at: geoDataURL, withIntermediateDirectories: true)
    try """
    mixed-port: 7890
    external-controller: '127.0.0.1:9090'
    unified-delay: false
    tcp-concurrent: false
    dns:
      enable: true
      listen: '127.0.0.1:5334'
    rules:
      - MATCH,DIRECT
    """.write(to: sourceURL, atomically: true, encoding: .utf8)
    try Data("geoip".utf8).write(to: geoDataURL.appendingPathComponent("GEOIP.dat"))
    try Data("geosite".utf8).write(to: geoDataURL.appendingPathComponent("GEOSITE.dat"))

    let occupiedTCP = Set([7890, 9090, 5334])
    let occupiedUDP = Set([5334])
    let preparer = RuntimeConfigurationPreparer(
        geoDataSourceURL: geoDataURL,
        portAllocator: RuntimePortAllocator(
            isTCPPortAvailable: { _, port in !occupiedTCP.contains(port) },
            isUDPPortAvailable: { _, port in !occupiedUDP.contains(port) }
        )
    )

    let prepared = try preparer.prepare(sourceURL: sourceURL, runtimeDirectoryURL: runtimeURL)
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)

    #expect(source.contains("mixed-port: 7890"))
    #expect(source.contains("unified-delay: false"))
    #expect(source.contains("tcp-concurrent: false"))
    #expect(runtime.contains("mixed-port: 7891"))
    #expect(runtime.contains("external-controller: '127.0.0.1:9091'"))
    #expect(runtime.contains("unified-delay: true"))
    #expect(runtime.contains("tcp-concurrent: true"))
    #expect(runtime.contains("listen: '127.0.0.1:5335'"))
    #expect(prepared.mixedPort == 7891)
    #expect(prepared.controllerURL.absoluteString == "http://127.0.0.1:9091")
    #expect(prepared.dnsListenPort == 5335)
    #expect(FileManager.default.fileExists(atPath: runtimeURL.appendingPathComponent("geoip.dat").path))
    #expect(FileManager.default.fileExists(atPath: runtimeURL.appendingPathComponent("geosite.dat").path))
}

@MainActor
@Test func appStoreImportsAndSelectsManagedConfiguration() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("configtest.yaml")
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    mixed-port: 7788
    external-controller: 127.0.0.1:9191
    mode: direct
    tun:
      enable: false
    proxies: []
    rules:
      - MATCH,DIRECT
    """.write(to: sourceURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: executableURL),
        profileRepository: repository
    )

    await store.importManagedProfile(from: sourceURL)

    #expect(store.managedProfiles.count == 1)
    #expect(store.selectedManagedProfileID == store.managedProfiles.first?.id)
    #expect(store.configPath == repository.runtimeConfigURL.path)
    #expect(store.httpPort == 7788)
    #expect(store.socksPort == 7788)
    #expect(store.selectedMode == .direct)
    #expect(store.isTunEnabled == false)
    #expect(store.controllerURL.absoluteString == "http://127.0.0.1:9191")
    #expect(store.lastErrorMessage == nil)
    #expect(store.validationState(for: try #require(store.selectedManagedProfileID)).kind == .valid)
}

@MainActor
@Test func appStoreStoresPerProfileValidationFailures() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("broken.yaml")
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: sourceURL, atomically: true, encoding: .utf8)
    try """
    #!/bin/sh
    if [ "$1" = "-t" ]; then
      echo 'profile rejected' >&2
      exit 1
    fi
    exit 0
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: executableURL),
        profileRepository: repository
    )

    await store.validateManagedProfile(profile.id)

    #expect(store.validationState(for: profile.id).kind == .invalid)
    #expect(store.validationState(for: profile.id).message == "profile rejected")
    #expect(store.lastErrorMessage == "profile rejected")
}

@MainActor
@Test func appStoreValidateAllProfilesRecordsEveryResult() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let validURL = directory.appendingPathComponent("valid.yaml")
    let brokenURL = directory.appendingPathComponent("broken.yaml")
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: validURL, atomically: true, encoding: .utf8)
    try "mixed-port: 7891\nbroken-marker: true\nrules:\n  - MATCH,DIRECT\n"
        .write(to: brokenURL, atomically: true, encoding: .utf8)
    try """
    #!/bin/sh
    config=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-f" ]; then
        shift
        config="$1"
      fi
      shift
    done
    if grep -q 'broken-marker' "$config"; then
      echo 'broken profile rejected' >&2
      exit 1
    fi
    exit 0
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let validProfile = try await repository.importProfile(from: validURL, name: "Valid") { _ in .success }
    let brokenProfile = try await repository.importProfile(from: brokenURL, name: "Broken") { _ in .success }
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: executableURL),
        profileRepository: repository
    )

    await store.validateAllManagedProfiles()

    #expect(store.validationState(for: validProfile.id).kind == .valid)
    #expect(store.validationState(for: brokenProfile.id).kind == .invalid)
    #expect(store.validationState(for: brokenProfile.id).message == "broken profile rejected")
    #expect(store.lastErrorMessage == "Broken: broken profile rejected")
}

@MainActor
@Test func networkIdentityRefreshClearsStaleCountryWhenLookupFails() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-curl")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try """
    #!/bin/sh
    echo 'lookup failed' >&2
    exit 7
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
        networkIdentityService: NetworkIdentityService(
            directFetcher: DirectNetworkIdentityFetcher(executableURL: executableURL),
            systemTunnelDetector: { false }
        )
    )
    store.externalIP = "151.242.36.41"
    store.networkCountryCode = "JP"
    store.networkCountryName = "Japan"

    await store.refreshNetworkIdentity()

    #expect(store.externalIP == "Unavailable")
    #expect(store.networkCountryCode.isEmpty)
    #expect(store.networkCountryName.isEmpty)
    #expect(store.networkEgressKind == .unavailable)
}

@MainActor
@Test func networkIdentityRefreshFallsBackToDirectWhenStartedProxyLookupFails() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-curl")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try """
    #!/bin/sh
    printf '%s' '{"success":true,"ip":"203.0.113.8","country_code":"US","country":"United States"}'
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
        networkIdentityService: NetworkIdentityService(
            directFetcher: DirectNetworkIdentityFetcher(executableURL: executableURL),
            systemTunnelDetector: { false }
        )
    )
    store.isStarted = true
    store.httpPort = 1

    await store.refreshNetworkIdentity()

    #expect(store.externalIP == "203.0.113.8")
    #expect(store.networkCountryCode == "US")
    #expect(store.networkCountryName == "United States")
    #expect(store.networkEgressKind == .direct)
}

@MainActor
@Test func appStoreRunsNetworkDoctorFromCurrentRouteState() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-curl")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try """
    #!/bin/sh
    printf '%s' '{"success":true,"ip":"151.242.36.41","country_code":"JP","country":"Japan"}'
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
        networkIdentityService: NetworkIdentityService(
            directFetcher: DirectNetworkIdentityFetcher(executableURL: executableURL),
            systemTunnelDetector: { true }
        ),
        networkPortProbe: { targets in
            targets.map { target in
                NetworkPortCheck(
                    label: target.label,
                    port: target.port,
                    isListening: target.port == 7890,
                    ownerName: target.port == 7890 ? "ClashGlas" : nil,
                    ownerPID: target.port == 7890 ? 97948 : nil
                )
            }
        },
        networkDNSProbe: { targets in
            targets.map { target in
                NetworkDNSCheck(
                    host: target.host,
                    addresses: target.host == "github.com" ? ["140.82.112.4"] : ["104.21.1.1"]
                )
            }
        },
        networkEndpointProbe: { targets in
            targets.map { target in
                NetworkEndpointCheck(
                    name: target.name,
                    url: target.url,
                    isReachable: true,
                    statusCode: 200,
                    latencyMilliseconds: 142,
                    errorMessage: nil
                )
            }
        }
    )

    await store.runNetworkDiagnosis()

    #expect(store.externalIP == "151.242.36.41")
    #expect(store.networkEgressKind == .systemTunnel)
    #expect(store.networkDiagnosticReport.severity == .warning)
    #expect(store.networkDiagnosticReport.summary.contains("System tunnel"))
    #expect(store.networkDiagnosticReport.copyText.contains("151.242.36.41"))
    #expect(store.networkPortChecks.count == 3)
    #expect(store.networkDNSChecks.count == 3)
    #expect(store.networkEndpointChecks.count == 2)
    #expect(store.networkDiagnosticReport.copyText.contains("ClashGlas"))
    #expect(store.networkDiagnosticReport.copyText.contains("DNS resolution"))
    #expect(store.networkDiagnosticReport.copyText.contains("External probes"))
}

@MainActor
@Test func appStoreLoadsPersistedManagedProfiles() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("profile.yaml")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: sourceURL, atomically: true, encoding: .utf8)
    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }
    try repository.select(profile.id)

    let store = AppStore(profileRepository: repository)

    #expect(store.managedProfiles.map(\.id) == [profile.id])
    #expect(store.selectedManagedProfileID == profile.id)
}

@MainActor
@Test func appStoreRenameUpdatesTheSelectedMenuBarProfileTitle() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("profile.yaml")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: sourceURL, atomically: true, encoding: .utf8)
    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }
    try repository.select(profile.id)
    let store = AppStore(profileRepository: repository)

    store.renameManagedProfile(profile.id, to: "Office Route")

    #expect(store.selectedManagedProfile?.name == "Office Route")
    #expect(store.menuBarProfileTitle == "Office Route")
    #expect(store.lastErrorMessage == nil)
}

@Test func coreRestartIntentPreservesTheCurrentRuntimeLevel() {
    #expect(CoreRestartIntent.resolve(isStarted: false, isCoreRunning: false) == .startController)
    #expect(CoreRestartIntent.resolve(isStarted: false, isCoreRunning: true) == .restartController)
    #expect(CoreRestartIntent.resolve(isStarted: true, isCoreRunning: true) == .restartActiveRuntime)
}

@MainActor
@Test func outboundModeSelectionAppliesWhileControllerOnly() async {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = AppStore(
        apiService: MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:1")!)
        ),
        profileRepository: ManagedProfileRepository(rootURL: rootURL)
    )
    store.isCoreRunning = true

    await store.setOutboundMode(.global)

    #expect(store.selectedMode == .rule)
    #expect(store.stagedOutboundMode == nil)
    #expect(store.lastErrorMessage != nil)
}

@Test func routingInputNormalizerExtractsLowercaseDomain() throws {
    #expect(
        try RoutingInputNormalizer.domain(
            from: " HTTPS://Sub.Example.COM:8443/path?q=1 "
        ) == "sub.example.com"
    )
    #expect(try RoutingInputNormalizer.domain(from: "example.com.") == "example.com")
    #expect(throws: RoutingInputError.self) {
        try RoutingInputNormalizer.domain(from: "localhost")
    }
    #expect(throws: RoutingInputError.self) {
        try RoutingInputNormalizer.domain(from: "192.0.2.10")
    }
}

@Test func routingOverrideRepositoryReplacesDuplicatesAndIsolatesProfiles() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let profileA = UUID()
    let profileB = UUID()
    let repository = RoutingOverrideRepository(rootURL: rootURL)

    try repository.upsert(domain: "example.com", policy: .vpn, profileID: profileA)
    try repository.upsert(domain: "example.com", policy: .direct, profileID: profileA)
    try repository.upsert(domain: "example.org", policy: .vpn, profileID: profileB)

    #expect(
        try repository.overrides(profileID: profileA)
            == [RoutingOverride(domain: "example.com", policy: .direct)]
    )
    #expect(
        try repository.overrides(profileID: profileB)
            == [RoutingOverride(domain: "example.org", policy: .vpn)]
    )

    try repository.remove(domain: "example.com", profileID: profileA)
    #expect(try repository.overrides(profileID: profileA).isEmpty)
}

@Test func runtimeConfigurationPreparerInjectsRoutingOverridesBeforeSubscriptionRules() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("source.yaml")
    let runtimeURL = directory.appendingPathComponent("Runtime", isDirectory: true)
    let geoDataURL = directory.appendingPathComponent("GeoData", isDirectory: true)
    try FileManager.default.createDirectory(at: geoDataURL, withIntermediateDirectories: true)
    try """
    mixed-port: 7890
    external-controller: 127.0.0.1:9090
    proxy-groups:
      - name: Mutdot
        type: select
        proxies:
          - DIRECT
    rules:
        - MATCH,DIRECT
    """.write(to: sourceURL, atomically: true, encoding: .utf8)
    try Data("geoip".utf8).write(to: geoDataURL.appendingPathComponent("GEOIP.dat"))
    try Data("geosite".utf8).write(to: geoDataURL.appendingPathComponent("GEOSITE.dat"))
    let preparer = RuntimeConfigurationPreparer(
        geoDataSourceURL: geoDataURL,
        portAllocator: RuntimePortAllocator(
            isTCPPortAvailable: { _, _ in true },
            isUDPPortAvailable: { _, _ in true }
        )
    )

    let prepared = try preparer.prepare(
        sourceURL: sourceURL,
        runtimeDirectoryURL: runtimeURL,
        routingOverrides: [
            RoutingOverride(domain: "openai.com", policy: .vpn),
            RoutingOverride(domain: "example.cn", policy: .direct),
        ]
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)

    #expect(!source.contains("Nexora routing overrides"))
    #expect(runtime.contains("# Nexora routing overrides"))
    #expect(runtime.contains("    # Nexora routing overrides"))
    #expect(runtime.contains("'DOMAIN-SUFFIX,openai.com,Mutdot'"))
    #expect(runtime.contains("'DOMAIN-SUFFIX,example.cn,DIRECT'"))
    #expect(
        runtime.range(of: "DOMAIN-SUFFIX,openai.com,Mutdot")!.lowerBound
            < runtime.range(of: "MATCH,DIRECT")!.lowerBound
    )
}

@Test func runtimeConfigurationPreparerAddsRulesSectionForOverrides() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("source.yaml")
    let runtimeURL = directory.appendingPathComponent("Runtime", isDirectory: true)
    let geoDataURL = directory.appendingPathComponent("GeoData", isDirectory: true)
    try FileManager.default.createDirectory(at: geoDataURL, withIntermediateDirectories: true)
    try "mixed-port: 7890\nexternal-controller: 127.0.0.1:9090\n"
        .write(to: sourceURL, atomically: true, encoding: .utf8)
    try Data("geoip".utf8).write(to: geoDataURL.appendingPathComponent("GEOIP.dat"))
    try Data("geosite".utf8).write(to: geoDataURL.appendingPathComponent("GEOSITE.dat"))
    let preparer = RuntimeConfigurationPreparer(
        geoDataSourceURL: geoDataURL,
        portAllocator: RuntimePortAllocator(
            isTCPPortAvailable: { _, _ in true },
            isUDPPortAvailable: { _, _ in true }
        )
    )

    let prepared = try preparer.prepare(
        sourceURL: sourceURL,
        runtimeDirectoryURL: runtimeURL,
        routingOverrides: [RoutingOverride(domain: "openai.com", policy: .direct)]
    )
    let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)

    #expect(runtime.contains("rules:\n  # Nexora routing overrides"))
    #expect(runtime.contains("unified-delay: true"))
    #expect(runtime.contains("tcp-concurrent: true"))
}

@Test func routingVPNTargetResolverReadsInlineSelectorGroup() {
    let yaml = """
    proxy-groups:
      - { name: Mutdot, type: select, proxies: [DIRECT] }
      - { name: Auto, type: url-test, proxies: [DIRECT] }
    rules:
      - MATCH,Mutdot
    """

    #expect(RoutingVPNTargetResolver.target(from: yaml) == "Mutdot")
}
