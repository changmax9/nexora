import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class AppStore {
    private let userDefaults: UserDefaults
    private let coreService: MihomoCoreService
    private var apiService: MihomoAPIService
    private let systemProxyService: SystemProxyService
    private let profileRepository: ManagedProfileRepository
    private let runtimeConfigurationPreparer: RuntimeConfigurationPreparer
    private let networkIdentityService: NetworkIdentityService
    private let networkPortProbe: @Sendable ([NetworkPortTarget]) async -> [NetworkPortCheck]
    private let networkDNSProbe: @Sendable ([NetworkDNSTarget]) async -> [NetworkDNSCheck]
    private let networkEndpointProbe: @Sendable ([NetworkEndpointTarget]) async -> [NetworkEndpointCheck]
    private let proxySelectionRepository: ProxySelectionRepository
    private let routingOverrideRepository: RoutingOverrideRepository
    private var previousSystemProxySnapshot: SystemProxySnapshot?
    private var runtimeTickCount = 0
    private var trafficStreamTask: Task<Void, Never>?
    private var latestUploadBytesPerSecond = 0
    private var latestDownloadBytesPerSecond = 0
    private var confirmedOutboundMode: OutboundMode = .rule
    private var isApplyingOutboundMode = false
    private var pendingOutboundMode: OutboundMode?
    @ObservationIgnored private var runtimeTransitionWaiters: [CheckedContinuation<Void, Never>] = []
    private var runtimeGeneration = 0
    private var networkIdentityGeneration = 0
    private(set) var isRefreshingNetworkIdentity = false
    public private(set) var isRuntimeTransitioning = false
    public var selectedSection: AppSection = .dashboard
    public var isCoreRunning = false
    public var isStarted = false
    public var coreStatus: CoreRuntimeStatus = .stopped
    public var isSystemProxyEnabled = false
    public var isTunEnabled = false
    public var proxyHost = "127.0.0.1"
    public var networkService = "Wi-Fi"
    public var appearanceMode: AppAppearance = .system {
        didSet {
            userDefaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }
    public var accent: NexoraAccent = .terracotta {
        didSet {
            userDefaults.set(accent.rawValue, forKey: "accent")
        }
    }
    public var language: AppLanguage = .system {
        didSet {
            userDefaults.set(language.rawValue, forKey: "language")
        }
    }
    public var reduceMotion = false {
        didSet {
            userDefaults.set(reduceMotion, forKey: "reduceMotion")
        }
    }
    private var latencyTestURLStorage = LatencyTestPlan.defaultTestURL
    public var latencyTestURL: String {
        get { latencyTestURLStorage }
        set {
            latencyTestURLStorage = LatencyTestSettings.normalizedTestURL(newValue)
            userDefaults.set(latencyTestURLStorage, forKey: "latencyTestURL")
        }
    }
    private var latencyTestTimeoutMillisecondsStorage = LatencyTestPlan.defaultTimeoutMilliseconds
    public var latencyTestTimeoutMilliseconds: Int {
        get { latencyTestTimeoutMillisecondsStorage }
        set {
            latencyTestTimeoutMillisecondsStorage = LatencyTestSettings
                .normalizedTimeoutMilliseconds(newValue)
            userDefaults.set(latencyTestTimeoutMillisecondsStorage, forKey: "latencyTestTimeoutMilliseconds")
        }
    }
    public var httpPort = 7890
    public var socksPort = 7891
    public var selectedMode: OutboundMode = .rule
    public private(set) var stagedOutboundMode: OutboundMode?
    public private(set) var stagedTunEnabled: Bool?
    public var selectedProfile = "No Profile"
    public var configPath = "\(NSHomeDirectory())/.config/clash/config.yaml"
    public private(set) var managedProfiles: [ManagedProfile] = []
    public private(set) var selectedManagedProfileID: ManagedProfile.ID?
    var routingOverrides: [RoutingOverride] = []
    public private(set) var controllerURL = URL(string: "http://127.0.0.1:9090")!
    public private(set) var controllerSecret: String?
    public var externalIP = "Detecting..."
    public var networkCountryCode = ""
    public var networkCountryName = ""
    public var networkEgressKind: NetworkEgressKind = .detecting
    public private(set) var networkDiagnosticReport = NetworkDiagnosticReport.placeholder
    public private(set) var networkPortChecks: [NetworkPortCheck] = []
    public private(set) var networkDNSChecks: [NetworkDNSCheck] = []
    public private(set) var networkEndpointChecks: [NetworkEndpointCheck] = []
    public var intranetIP = "Detecting..."
    public var uploadSpeedText = "0B/s"
    public var downloadSpeedText = "0B/s"
    public var uploadTotalText = "0"
    public var downloadTotalText = "0"
    public var uploadTrafficUnit = "B"
    public var downloadTrafficUnit = "B"
    private(set) var trafficUsageTotals = TrafficUsageTotals.zero
    public var lastErrorMessage: String?
    public private(set) var profileValidationStates: [ManagedProfile.ID: ProfileValidationState] = [:]
    var isLatencyTesting = false
    var latencyTestProgress = LatencyTestProgress(completed: 0, total: 0)
    public var speedSamples: [Double] = Array(repeating: 0, count: 28)

    var proxyGroups: [ProxyGroup] = []
    var menuBarPreferredGroupName: String?
    var connections: [ConnectionEntry] = []

    public init(
        coreService: MihomoCoreService = MihomoCoreService(),
        apiService: MihomoAPIService = MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
        ),
        systemProxyService: SystemProxyService = SystemProxyService(),
        profileRepository: ManagedProfileRepository = ManagedProfileRepository(),
        runtimeConfigurationPreparer: RuntimeConfigurationPreparer = RuntimeConfigurationPreparer(),
        networkIdentityService: NetworkIdentityService = NetworkIdentityService(),
        networkPortProbe: @escaping @Sendable ([NetworkPortTarget]) async -> [NetworkPortCheck] = NetworkPortProbe.check,
        networkDNSProbe: @escaping @Sendable ([NetworkDNSTarget]) async -> [NetworkDNSCheck] = NetworkDNSProbe.resolve,
        networkEndpointProbe: @escaping @Sendable ([NetworkEndpointTarget]) async -> [NetworkEndpointCheck] = NetworkEndpointProbe.check,
        proxySelectionRepository: ProxySelectionRepository? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        self.coreService = coreService
        self.apiService = apiService
        self.systemProxyService = systemProxyService
        self.profileRepository = profileRepository
        self.runtimeConfigurationPreparer = runtimeConfigurationPreparer
        self.networkIdentityService = networkIdentityService
        self.networkPortProbe = networkPortProbe
        self.networkDNSProbe = networkDNSProbe
        self.networkEndpointProbe = networkEndpointProbe
        self.proxySelectionRepository = proxySelectionRepository
            ?? ProxySelectionRepository(rootURL: profileRepository.rootURL)
        routingOverrideRepository = RoutingOverrideRepository(rootURL: profileRepository.rootURL)
        appearanceMode = AppAppearance(
            rawValue: userDefaults.string(forKey: "appearanceMode") ?? ""
        ) ?? .system
        accent = NexoraAccent(
            rawValue: userDefaults.string(forKey: "accent") ?? ""
        ) ?? .terracotta
        language = AppLanguage(
            rawValue: userDefaults.string(forKey: "language") ?? ""
        ) ?? .system
        reduceMotion = userDefaults.bool(forKey: "reduceMotion")
        latencyTestURLStorage = LatencyTestSettings.normalizedTestURL(
            userDefaults.string(forKey: "latencyTestURL") ?? LatencyTestPlan.defaultTestURL
        )
        if userDefaults.object(forKey: "latencyTestTimeoutMilliseconds") != nil {
            latencyTestTimeoutMillisecondsStorage = LatencyTestSettings.normalizedTimeoutMilliseconds(
                userDefaults.integer(forKey: "latencyTestTimeoutMilliseconds")
            )
        }
        controllerURL = apiService.requestBuilder.baseURL
        controllerSecret = apiService.requestBuilder.secret
        configPath = profileRepository.runtimeConfigURL.path
        reloadManagedProfiles()
        reloadRoutingOverrides()
        if let profile = selectedManagedProfile {
            synchronizeConfiguration(from: profile.managedConfigURL)
        }
        coreService.onUnexpectedTermination = { [weak self] message in
            self?.handleCoreFailure(message)
        }
    }

    public var selectedManagedProfile: ManagedProfile? {
        guard let selectedManagedProfileID else {
            return nil
        }
        return managedProfiles.first { $0.id == selectedManagedProfileID }
    }

    public func text(_ key: AppString) -> String {
        language.text(key)
    }

    public var menuBarProfileTitle: String {
        selectedManagedProfile?.name ?? selectedProfile
    }

    var menuBarHeaderTitle: String {
        menuBarSelectedNodeName ?? menuBarProfileTitle
    }

    var latencyTestSettings: LatencyTestSettings {
        LatencyTestSettings(
            testURL: latencyTestURL,
            timeoutMilliseconds: latencyTestTimeoutMilliseconds
        )
    }

    var menuBarSelector: ProxyGroup? {
        MenuBarProxyResolver.resolve(
            groups: proxyGroups,
            mode: selectedMode,
            preferredName: menuBarPreferredGroupName
        )
    }

    var menuBarProxyNodes: [ProxyNode] {
        menuBarSelector?.nodes ?? []
    }

    var menuBarSelectedNodeName: String? {
        guard let selector = menuBarSelector else { return nil }
        return ProxySelectionResolver.selectedLeafNodeName(
            selectedGroupName: selector.name,
            groups: proxyGroups
        )
    }

    public var managedProfilesFolderURL: URL {
        profileRepository.rootURL.appendingPathComponent("Profiles", isDirectory: true)
    }

    public func validationState(for id: ManagedProfile.ID) -> ProfileValidationState {
        profileValidationStates[id] ?? .notValidated
    }

    public func importManagedProfile(from sourceURL: URL) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        do {
            let profile = try await profileRepository.importProfile(from: sourceURL) { [coreService] stagedURL in
                await coreService.validateConfig(path: stagedURL.path)
            }
            _ = await activateManagedProfile(profile)
            profileValidationStates[profile.id] = .valid()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func selectManagedProfile(_ id: ManagedProfile.ID) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        guard let profile = managedProfiles.first(where: { $0.id == id }) else {
            lastErrorMessage = ManagedProfileError.profileNotFound.localizedDescription
            return
        }
        _ = await activateManagedProfile(profile)
    }

    public func removeManagedProfile(_ id: ManagedProfile.ID) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        do {
            if id == selectedManagedProfileID {
                if let replacement = managedProfiles.first(where: { $0.id != id }) {
                    guard await activateManagedProfile(replacement) else { return }
                } else if isStarted {
                    await stopRuntime(userInitiated: true)
                } else {
                    await stopControllerOnly(userInitiated: true)
                }
            }
            try profileRepository.remove(id)
            try? routingOverrideRepository.removeProfile(id)
            profileValidationStates.removeValue(forKey: id)
            reloadManagedProfiles()
            reloadRoutingOverrides()
            if selectedManagedProfile == nil {
                stagedOutboundMode = nil
                stagedTunEnabled = nil
                selectedMode = .rule
                confirmedOutboundMode = .rule
                isTunEnabled = false
                proxyGroups = []
                connections = []
                if FileManager.default.fileExists(atPath: profileRepository.runtimeConfigURL.path) {
                    try FileManager.default.removeItem(at: profileRepository.runtimeConfigURL)
                }
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func renameManagedProfile(_ id: ManagedProfile.ID, to name: String) {
        do {
            try profileRepository.rename(id, to: name)
            reloadManagedProfiles()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func validateManagedProfile(_ id: ManagedProfile.ID) async {
        guard let profile = managedProfiles.first(where: { $0.id == id }) else {
            lastErrorMessage = ManagedProfileError.profileNotFound.localizedDescription
            return
        }
        profileValidationStates[id] = .checking
        switch await coreService.validateConfig(path: profile.managedConfigURL.path) {
        case .success:
            profileValidationStates[id] = .valid()
            lastErrorMessage = nil
        case let .failure(message):
            profileValidationStates[id] = .invalid(message)
            lastErrorMessage = message
        }
    }

    public func validateAllManagedProfiles() async {
        var firstFailure: String?
        for profile in managedProfiles {
            profileValidationStates[profile.id] = .checking
            switch await coreService.validateConfig(path: profile.managedConfigURL.path) {
            case .success:
                profileValidationStates[profile.id] = .valid()
            case let .failure(message):
                profileValidationStates[profile.id] = .invalid(message)
                if firstFailure == nil {
                    firstFailure = "\(profile.name): \(message)"
                }
            }
        }
        lastErrorMessage = firstFailure
    }

    func addRoutingOverride(input: String, policy: RoutingPolicy) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        guard let profileID = selectedManagedProfileID else {
            lastErrorMessage = "Select a managed profile before adding routing rules."
            return
        }
        do {
            let domain = try RoutingInputNormalizer.domain(from: input)
            if policy == .vpn,
               let profile = selectedManagedProfile {
                let yaml = try String(
                    contentsOf: profile.managedConfigURL,
                    encoding: .utf8
                )
                guard RoutingVPNTargetResolver.target(from: yaml) != nil else {
                    throw RuntimeConfigurationError.missingVPNPolicyGroup
                }
            }
            try routingOverrideRepository.upsert(
                domain: domain,
                policy: policy,
                profileID: profileID
            )
            reloadRoutingOverrides()
            try await restartRuntimeForRoutingChangesIfNeeded()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeRoutingOverride(domain: String) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        guard let profileID = selectedManagedProfileID else {
            return
        }
        do {
            try routingOverrideRepository.remove(domain: domain, profileID: profileID)
            reloadRoutingOverrides()
            try await restartRuntimeForRoutingChangesIfNeeded()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func toggleRuntime(configPath: String) async {
        guard !isRuntimeTransitioning else { return }
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        if isStarted {
            await stopRuntime(userInitiated: true)
            return
        }
        _ = await startRuntime(configPath: configPath)
    }

    private func startRuntime(configPath: String) async -> Bool {
        runtimeGeneration += 1
        let requestedMode = stagedOutboundMode
        let requestedTun = stagedTunEnabled
        guard await ensureControllerAvailable(configPath: configPath) else {
            return false
        }
        if let requestedMode,
           !(await applyOutboundModeToController(requestedMode)) {
            return false
        }
        if let requestedTun,
           !(await applyTunToController(requestedTun)) {
            return false
        }
        guard coreService.isProcessRunning else {
            handleCoreFailure(coreService.status.failureMessage ?? "Mihomo exited unexpectedly.")
            return false
        }

        isStarted = true
        isCoreRunning = true
        runtimeTickCount = 0
        latestUploadBytesPerSecond = 0
        latestDownloadBytesPerSecond = 0
        startTrafficStream()
        await refreshRuntimeConfiguration()
        await fetchProxies()
        await refreshConnections()
        guard coreService.isProcessRunning else {
            handleCoreFailure(coreService.status.failureMessage ?? "Mihomo exited unexpectedly.")
            return false
        }
        await applySystemProxy(enabled: true, service: networkService)
        await refreshNetworkIdentity()
        return isStarted && lastErrorMessage == nil
    }

    public func shutdownRuntime() async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        if isStarted {
            await stopRuntime(userInitiated: true)
        } else if isCoreRunning {
            await stopControllerOnly(userInitiated: true)
        }
    }

    public func restartCore() async {
        guard !isRuntimeTransitioning else { return }
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        let intent = CoreRestartIntent.resolve(
            isStarted: isStarted,
            isCoreRunning: isCoreRunning
        )
        let activeMode = selectedMode

        switch intent {
        case .startController:
            guard await ensureControllerAvailable(configPath: configPath) else {
                return
            }
            if confirmedOutboundMode != activeMode {
                guard await applyOutboundModeToController(activeMode) else { return }
            }
            await fetchProxies()
        case .restartController:
            await stopControllerOnly(userInitiated: true)
            guard await ensureControllerAvailable(configPath: configPath) else {
                return
            }
            if confirmedOutboundMode != activeMode {
                guard await applyOutboundModeToController(activeMode) else { return }
            }
            await fetchProxies()
        case .restartActiveRuntime:
            stagedOutboundMode = activeMode
            await stopRuntime(userInitiated: true)
            _ = await startRuntime(configPath: configPath)
        }
    }

    public func shutdownForApplicationTermination() {
        stopTrafficStream()
        if let previousSystemProxySnapshot {
            try? systemProxyService.apply(
                .restore(service: networkService, snapshot: previousSystemProxySnapshot)
            )
            self.previousSystemProxySnapshot = nil
        }
        coreService.stopImmediately()
        coreStatus = coreService.status
        isStarted = false
        isCoreRunning = false
        isSystemProxyEnabled = false
    }

    public func toggleSystemProxy(service: String = "Wi-Fi") async {
        guard !isRuntimeTransitioning else { return }
        guard isStarted else {
            isSystemProxyEnabled.toggle()
            return
        }
        await applySystemProxy(enabled: !isSystemProxyEnabled, service: service)
    }

    public func setSystemProxyEnabled(_ enabled: Bool) {
        isSystemProxyEnabled = enabled
    }

    public func currentSystemProxyCommand(service: String) -> SystemProxyCommand {
        if isSystemProxyEnabled {
            return .enable(service: service, host: proxyHost, httpPort: httpPort, socksPort: socksPort)
        }
        return .disable(service: service)
    }

    public func setOutboundMode(_ mode: OutboundMode) async {
        selectedMode = mode
        guard isCoreRunning else {
            stagedOutboundMode = mode
            lastErrorMessage = nil
            return
        }
        stagedOutboundMode = nil
        pendingOutboundMode = mode
        guard !isApplyingOutboundMode else {
            return
        }
        isApplyingOutboundMode = true
        await beginRuntimeTransition()
        defer {
            isApplyingOutboundMode = false
            endRuntimeTransition()
        }
        while let requestedMode = pendingOutboundMode {
            pendingOutboundMode = nil
            switch await requestOutboundModeFromController(requestedMode) {
            case let .success(effectiveMode):
                confirmedOutboundMode = effectiveMode
                if pendingOutboundMode == nil {
                    selectedMode = effectiveMode
                    lastErrorMessage = nil
                }
            case let .failure(error):
                if pendingOutboundMode == nil {
                    selectedMode = confirmedOutboundMode
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func setTunEnabled(_ enabled: Bool) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        let previousValue = isTunEnabled
        isTunEnabled = enabled
        guard isStarted else {
            stagedTunEnabled = enabled
            lastErrorMessage = nil
            return
        }
        if !(await applyTunToController(enabled)) {
            isTunEnabled = previousValue
        }
    }

    public func selectProxy(groupName: String, nodeName: String) {
        guard let groupIndex = proxyGroups.firstIndex(where: { $0.name == groupName }) else {
            return
        }
        for nodeIndex in proxyGroups[groupIndex].nodes.indices {
            proxyGroups[groupIndex].nodes[nodeIndex].isSelected = proxyGroups[groupIndex].nodes[nodeIndex].name == nodeName
        }
    }

    public func selectProxyRemote(groupName: String, nodeName: String) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        guard await ensureControllerAvailable(configPath: configPath) else {
            return
        }
        let targetGroups = ProxySelectionResolver.targetGroups(
            selectedGroupName: groupName,
            nodeName: nodeName,
            groups: proxyGroups
        )
        guard !targetGroups.isEmpty else {
            lastErrorMessage = "This automatic group cannot be manually locked without a parent selector."
            return
        }
        do {
            for targetGroup in targetGroups {
                _ = try await apiService.data(
                    for: .changeProxy(group: targetGroup, proxy: nodeName)
                )
                selectProxy(groupName: targetGroup, nodeName: nodeName)
                if let profileID = selectedManagedProfileID {
                    try proxySelectionRepository.save(
                        selector: targetGroup,
                        node: nodeName,
                        profileID: profileID
                    )
                }
            }
            _ = try await apiService.data(for: .closeAllConnections)
            lastErrorMessage = nil
            await fetchProxies()
            if isStarted {
                await refreshNetworkIdentity()
            }
        } catch {
            let message = error.localizedDescription
            // A later failure (including closing old connections) cannot undo a
            // selector change already accepted by the controller.
            await fetchProxies()
            lastErrorMessage = message
            if isStarted { await refreshNetworkIdentity() }
        }
    }

    public func delayTestAll() async {
        guard !isLatencyTesting else {
            return
        }
        isLatencyTesting = true
        defer { isLatencyTesting = false }
        await beginRuntimeTransition()
        let controllerAvailable = await ensureControllerAvailable(configPath: configPath)
        endRuntimeTransition()
        guard controllerAvailable else {
            return
        }
        let settings = latencyTestSettings
        let plan = LatencyTestPlanner.plan(groups: proxyGroups, settings: settings)
        let service = apiService
        guard !plan.nodeNames.isEmpty else {
            lastErrorMessage = "No concrete proxy nodes are available for latency testing."
            return
        }
        let generation = runtimeGeneration
        latencyTestProgress = LatencyTestProgress(completed: 0, total: plan.nodeNames.count)
        for groupIndex in proxyGroups.indices {
            for nodeIndex in proxyGroups[groupIndex].nodes.indices
            where plan.nodeNames.contains(proxyGroups[groupIndex].nodes[nodeIndex].name) {
                proxyGroups[groupIndex].nodes[nodeIndex].latency = nil
            }
        }

        var successfulNodeNames = Set<String>()
        var completedNodeNames = Set<String>()
        var fallbackTestsByName = Dictionary(
            uniqueKeysWithValues: plan.fallbackTests.map { ($0.proxyName, $0) }
        )
        func publish(
            delays: [String: Int],
            completed names: Set<String>
        ) {
            guard generation == runtimeGeneration else { return }
            completedNodeNames.formUnion(names)
            latencyTestProgress = LatencyTestProgress(
                completed: completedNodeNames.count,
                total: plan.nodeNames.count
            )
            successfulNodeNames.formUnion(delays.keys)
            for (nodeName, latency) in delays {
                for groupIndex in proxyGroups.indices {
                    for nodeIndex in proxyGroups[groupIndex].nodes.indices
                    where proxyGroups[groupIndex].nodes[nodeIndex].name == nodeName {
                        proxyGroups[groupIndex].nodes[nodeIndex].latency = latency
                    }
                }
            }
        }

        for batchStart in stride(
            from: 0,
            to: plan.groupTests.count,
            by: LatencyTestPlan.maximumConcurrentGroupTests
        ) {
            let batchEnd = min(
                batchStart + LatencyTestPlan.maximumConcurrentGroupTests,
                plan.groupTests.count
            )
            let batch = plan.groupTests[batchStart..<batchEnd]
            await withTaskGroup(of: (LatencyGroupTest, [String: Int]).self) { taskGroup in
                for test in batch {
                    taskGroup.addTask {
                        let delays = (try? await service.groupDelays(
                            group: test.groupName,
                            url: test.url,
                            timeout: settings.timeoutMilliseconds
                        )) ?? [:]
                        return (test, delays)
                    }
                }
                for await (test, delays) in taskGroup {
                    let validDelays = delays.filter { nodeName, delay in
                        test.nodeNames.contains(nodeName)
                            && LatencyTestSettings.validMeasuredDelay(delay) != nil
                    }
                    let measuredNodeNames = Set(validDelays.keys)
                    publish(delays: validDelays, completed: measuredNodeNames)
                    for fallback in test.fallbackTests(excluding: measuredNodeNames) {
                        fallbackTestsByName[fallback.proxyName] = fallback
                    }
                }
            }
        }

        let fallbackTests = fallbackTestsByName.values
            .filter { !successfulNodeNames.contains($0.proxyName) }
            .sorted { $0.proxyName < $1.proxyName }
        for batchStart in stride(
            from: 0,
            to: fallbackTests.count,
            by: LatencyTestPlan.maximumConcurrentFallbackTests
        ) {
            let batchEnd = min(
                batchStart + LatencyTestPlan.maximumConcurrentFallbackTests,
                fallbackTests.count
            )
            let batch = fallbackTests[batchStart..<batchEnd]
            await withTaskGroup(of: (String, Int?).self) { taskGroup in
                for test in batch {
                    taskGroup.addTask {
                        let latency = await service.proxyDelay(
                            proxy: test.proxyName,
                            url: test.url,
                            timeout: settings.timeoutMilliseconds
                        )
                        return (test.proxyName, latency)
                    }
                }
                for await (nodeName, latency) in taskGroup {
                    publish(
                        delays: latency.map { [nodeName: $0] } ?? [:],
                        completed: [nodeName]
                    )
                }
            }
        }
        guard generation == runtimeGeneration else { return }
        lastErrorMessage = !successfulNodeNames.isEmpty
            ? nil
            : "No proxy returned a successful delay measurement."
    }

    func closeConnection(_ connection: ConnectionEntry) async {
        guard let remoteID = connection.remoteID else {
            return
        }
        do {
            _ = try await apiService.data(for: .closeConnection(id: remoteID))
            connections.removeAll { $0.remoteID == remoteID }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func closeAllConnections() async {
        do {
            _ = try await apiService.data(for: .closeAllConnections)
            connections.removeAll()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        await refreshConnections()
    }

    public func refreshRuntimeConfiguration() async {
        let generation = runtimeGeneration
        do {
            let data = try await apiService.data(for: .configs)
            let config = try MihomoAPIDecoder.runtimeConfig(from: data)
            guard generation == runtimeGeneration else { return }
            if let mixedPort = config.mixedPort {
                httpPort = mixedPort
                socksPort = mixedPort
            }
            selectedMode = stagedOutboundMode ?? config.mode
            confirmedOutboundMode = config.mode
            isTunEnabled = stagedTunEnabled ?? config.tunEnabled
            lastErrorMessage = nil
        } catch {
            guard generation == runtimeGeneration else { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    public func runtimeTick() async {
        guard !isRuntimeTransitioning, isCoreRunning || isStarted else {
            return
        }
        guard coreService.isProcessRunning else {
            handleCoreFailure(coreService.status.failureMessage ?? "Mihomo exited unexpectedly.")
            return
        }
        guard isStarted else { return }
        let generation = runtimeGeneration
        runtimeTickCount += 1
        advanceSpeedGraph()
        if runtimeTickCount.isMultiple(of: 4) {
            await refreshConnections()
        }
        guard generation == runtimeGeneration, !isRuntimeTransitioning, isStarted else { return }
        if runtimeTickCount.isMultiple(of: 10) {
            await refreshRuntimeConfiguration()
        }
        guard generation == runtimeGeneration, !isRuntimeTransitioning, isStarted else { return }
        if runtimeTickCount.isMultiple(of: 20) {
            await refreshNetworkIdentity()
        }
    }

    public func refreshProxies() async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        guard !Task.isCancelled else { return }
        guard await ensureControllerAvailable(configPath: configPath) else {
            return
        }
        await fetchProxies()
    }

    private func fetchProxies() async {
        let generation = runtimeGeneration
        do {
            let data = try await apiService.data(for: .proxies)
            guard generation == runtimeGeneration else { return }
            applyProxyResponse(data)
            lastErrorMessage = nil
        } catch {
            guard generation == runtimeGeneration else { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    public func refreshProxiesAndLatency() async {
        await refreshProxies()
        guard lastErrorMessage == nil, !proxyGroups.isEmpty else {
            return
        }
        await delayTestAll()
    }

    public func refreshConnections() async {
        guard isStarted else {
            return
        }
        let generation = runtimeGeneration
        do {
            let data = try await apiService.data(for: .connections)
            guard generation == runtimeGeneration, isStarted else { return }
            applyConnectionsResponse(data)
            lastErrorMessage = nil
        } catch {
            guard generation == runtimeGeneration, isStarted else { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applyProxyResponse(_ data: Data) {
        do {
            let measuredLatencies = Dictionary(
                proxyGroups
                    .flatMap(\.nodes)
                    .compactMap { node in
                        node.latency.map { (node.name, $0) }
                    },
                uniquingKeysWith: { current, _ in current }
            )
            var groups = try MihomoAPIDecoder.proxyGroups(from: data)
            for groupIndex in groups.indices {
                for nodeIndex in groups[groupIndex].nodes.indices {
                    let nodeName = groups[groupIndex].nodes[nodeIndex].name
                    groups[groupIndex].nodes[nodeIndex].latency = measuredLatencies[nodeName]
                        ?? groups[groupIndex].nodes[nodeIndex].latency
                }
            }
            proxyGroups = groups
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applyConnectionsResponse(_ data: Data) {
        do {
            let snapshot = try MihomoAPIDecoder.connectionsSnapshot(from: data)
            connections = snapshot.entries
            trafficUsageTotals = TrafficUsageTotals(
                uploadBytes: snapshot.uploadTotal,
                downloadBytes: snapshot.downloadTotal
            )
            let upload = Self.trafficAmount(trafficUsageTotals.uploadBytes)
            let download = Self.trafficAmount(trafficUsageTotals.downloadBytes)
            uploadTotalText = upload.value
            uploadTrafficUnit = upload.unit
            downloadTotalText = download.value
            downloadTrafficUnit = download.unit
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applyTrafficResponse(_ data: Data) {
        applyTrafficResponse(data, appendSample: true)
    }

    func applyLiveTrafficResponse(_ data: Data) {
        applyTrafficResponse(data, appendSample: false)
    }

    private func applyTrafficResponse(_ data: Data, appendSample: Bool) {
        do {
            let snapshot = try MihomoAPIDecoder.traffic(from: data)
            latestUploadBytesPerSecond = snapshot.up
            latestDownloadBytesPerSecond = snapshot.down
            uploadSpeedText = Self.speedText(snapshot.up)
            downloadSpeedText = Self.speedText(snapshot.down)
            if appendSample {
                appendSpeedSample(up: snapshot.up, down: snapshot.down)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applySystemProxy(enabled: Bool, service: String = "Wi-Fi") async {
        do {
            if enabled, previousSystemProxySnapshot == nil {
                previousSystemProxySnapshot = try? systemProxyService.capture(service: service)
            }
            if !enabled {
                restorePreviousSystemProxy()
                return
            }
            let command = enabled
                ? SystemProxyCommand.enable(service: service, host: proxyHost, httpPort: httpPort, socksPort: socksPort)
                : SystemProxyCommand.disable(service: service)
            try systemProxyService.apply(command)
            isSystemProxyEnabled = enabled
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            isSystemProxyEnabled = !enabled
        }
    }

    public func refreshNetworkIdentity() async {
        networkIdentityGeneration += 1
        let requestGeneration = networkIdentityGeneration
        let runtime = runtimeGeneration
        let shouldFetchViaProxy = isStarted
        let requestedHost = proxyHost
        let requestedPort = httpPort
        isRefreshingNetworkIdentity = true
        defer {
            if requestGeneration == networkIdentityGeneration {
                isRefreshingNetworkIdentity = false
            }
        }
        func isCurrentRequest() -> Bool {
            !Task.isCancelled && requestGeneration == networkIdentityGeneration
                && runtime == runtimeGeneration && shouldFetchViaProxy == isStarted
                && requestedHost == proxyHost && requestedPort == httpPort
        }
        if let localIP = networkIdentityService.localIPv4Address() {
            intranetIP = localIP
        }
        let directEgressKind: NetworkEgressKind = if await networkIdentityService.hasActiveSystemTunnel() {
            .systemTunnel
        } else {
            .direct
        }
        do {
            let identity: NetworkIdentity
            let resolvedEgress: NetworkEgressKind
            if shouldFetchViaProxy {
                do {
                    identity = try await networkIdentityService.fetchViaProxy(host: requestedHost, port: requestedPort)
                    resolvedEgress = .proxy
                } catch {
                    guard isCurrentRequest() else { return }
                    identity = try await networkIdentityService.fetchDirect()
                    resolvedEgress = directEgressKind
                }
            } else {
                identity = try await networkIdentityService.fetchDirect()
                resolvedEgress = directEgressKind
            }
            guard isCurrentRequest() else { return }
            guard NetworkAddressPolicy.isIPv4(identity.ip) else {
                throw NetworkIdentityError.invalidResponse(
                    "The network identity service returned IPv6."
                )
            }
            externalIP = identity.ip
            networkCountryCode = identity.countryCode
            networkCountryName = identity.countryName
            networkEgressKind = resolvedEgress
        } catch {
            guard isCurrentRequest() else { return }
            externalIP = "Unavailable"
            networkCountryCode = ""
            networkCountryName = ""
            networkEgressKind = .unavailable
        }
    }

    public func runNetworkDiagnosis() async {
        await refreshNetworkIdentity()
        let activeSystemTunnel = await networkIdentityService.hasActiveSystemTunnel()
        let targets = NetworkPortTarget.standard(
            httpPort: httpPort,
            socksPort: socksPort,
            controllerPort: controllerURL.port ?? 9090
        )
        async let portChecks = networkPortProbe(targets)
        async let dnsChecks = networkDNSProbe(NetworkDNSTarget.standard)
        async let endpointChecks = networkEndpointProbe(NetworkEndpointTarget.standard)
        networkPortChecks = await portChecks
        networkDNSChecks = await dnsChecks
        networkEndpointChecks = await endpointChecks
        networkDiagnosticReport = NetworkDiagnosticEngine.report(
            snapshot: NetworkDiagnosticSnapshot(
                isStarted: isStarted,
                isSystemProxyEnabled: isSystemProxyEnabled,
                isTunEnabled: isTunEnabled,
                activeSystemTunnel: activeSystemTunnel,
                egressKind: networkEgressKind,
                externalIP: externalIP,
                countryCode: networkCountryCode,
                countryName: networkCountryName,
                intranetIP: intranetIP,
                httpPort: httpPort,
                socksPort: socksPort,
                selectedMode: selectedMode,
                selectedProfile: menuBarProfileTitle,
                portChecks: networkPortChecks,
                dnsChecks: networkDNSChecks,
                endpointChecks: networkEndpointChecks
            )
        )
    }

    static func speedText(_ bytesPerSecond: Int) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1fMB/s", Double(bytesPerSecond) / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.1fKB/s", Double(bytesPerSecond) / 1_000)
        }
        return "\(bytesPerSecond)B/s"
    }

    static func trafficAmount(_ bytes: Int) -> (value: String, unit: String) {
        let value = Double(bytes)
        if value >= 1_000_000_000 {
            return (String(format: "%.1f", value / 1_000_000_000), "GB")
        }
        if value >= 1_000_000 {
            return (String(format: "%.1f", value / 1_000_000), "MB")
        }
        if value >= 1_000 {
            return (String(format: "%.1f", value / 1_000), "KB")
        }
        return ("\(bytes)", "B")
    }

    private func appendSpeedSample(up: Int, down: Int) {
        let sample = min(1.0, Double(max(up, down)) / 1_000_000)
        speedSamples.append(sample)
        if speedSamples.count > 28 {
            speedSamples.removeFirst(speedSamples.count - 28)
        }
    }

    func advanceSpeedGraph() {
        appendSpeedSample(
            up: latestUploadBytesPerSecond,
            down: latestDownloadBytesPerSecond
        )
    }

    private func startTrafficStream() {
        stopTrafficStream()
        let service = apiService
        trafficStreamTask = Task { [weak self] in
            while !Task.isCancelled, self?.isStarted == true {
                do {
                    for try await data in service.lineDataStream(for: .traffic) {
                        guard !Task.isCancelled, let self, self.isStarted else {
                            return
                        }
                        self.applyLiveTrafficResponse(data)
                    }
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
    }

    private func stopTrafficStream() {
        trafficStreamTask?.cancel()
        trafficStreamTask = nil
    }

    // Profile imports queue so a multi-file drop is not lost; repeated start taps are ignored.
    private func beginRuntimeTransition() async {
        if isRuntimeTransitioning {
            await withCheckedContinuation { runtimeTransitionWaiters.append($0) }
        } else {
            isRuntimeTransitioning = true
        }
    }

    private func endRuntimeTransition() {
        if runtimeTransitionWaiters.isEmpty {
            isRuntimeTransitioning = false
        } else {
            runtimeTransitionWaiters.removeFirst().resume()
        }
    }

    private func activateManagedProfile(_ profile: ManagedProfile) async -> Bool {
        guard profile.id != selectedManagedProfileID else { return true }
        let wasStarted = isStarted
        let wasCoreRunning = isCoreRunning || coreService.isProcessRunning
        do {
            // Check the source before taking down a working connection.
            _ = try MihomoConfigurationInspector.inspect(url: profile.managedConfigURL)
            if wasStarted {
                await stopRuntime(userInitiated: true)
            } else if wasCoreRunning {
                await stopControllerOnly(userInitiated: true)
            }
            try profileRepository.select(profile.id)
            reloadManagedProfiles()
            reloadRoutingOverrides()
            stagedOutboundMode = nil
            stagedTunEnabled = nil
            proxyGroups = []
            menuBarPreferredGroupName = nil
            connections = []
            runtimeGeneration += 1
            synchronizeConfiguration(from: profile.managedConfigURL)
            lastErrorMessage = nil
            if wasStarted {
                return await startRuntime(configPath: configPath)
            }
            if wasCoreRunning {
                guard await ensureControllerAvailable(configPath: configPath) else { return false }
                await fetchProxies()
            }
            return true
        } catch {
            reloadManagedProfiles()
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func handleCoreFailure(_ message: String) {
        runtimeGeneration += 1
        if isCoreRunning || isStarted {
            stagedOutboundMode = stagedOutboundMode ?? confirmedOutboundMode
        }
        if isStarted {
            stagedTunEnabled = isTunEnabled
        }
        stopTrafficStream()
        isStarted = false
        isCoreRunning = false
        coreStatus = .failed(message)
        runtimeTickCount = 0
        latestUploadBytesPerSecond = 0
        latestDownloadBytesPerSecond = 0
        uploadSpeedText = "0B/s"
        downloadSpeedText = "0B/s"
        speedSamples = Array(repeating: 0, count: 28)
        connections = []
        restorePreviousSystemProxy()
        lastErrorMessage = message
    }

    private func reloadManagedProfiles() {
        do {
            managedProfiles = try profileRepository.loadProfiles()
            selectedManagedProfileID = try profileRepository.selectedProfileID()
            let managedProfileIDs = Set(managedProfiles.map(\.id))
            profileValidationStates = profileValidationStates.filter {
                managedProfileIDs.contains($0.key)
            }
            if let selectedManagedProfile {
                selectedProfile = selectedManagedProfile.name
            } else {
                selectedProfile = "No Profile"
            }
        } catch {
            managedProfiles = []
            selectedManagedProfileID = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    private func reloadRoutingOverrides() {
        guard let profileID = selectedManagedProfileID else {
            routingOverrides = []
            return
        }
        do {
            routingOverrides = try routingOverrideRepository.overrides(profileID: profileID)
        } catch {
            routingOverrides = []
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyOutboundModeToController(_ mode: OutboundMode) async -> Bool {
        switch await requestOutboundModeFromController(mode) {
        case let .success(effectiveMode):
            selectedMode = effectiveMode
            confirmedOutboundMode = effectiveMode
            stagedOutboundMode = nil
            lastErrorMessage = nil
            return true
        case let .failure(error):
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func requestOutboundModeFromController(
        _ mode: OutboundMode
    ) async -> Result<OutboundMode, Error> {
        do {
            _ = try await apiService.data(
                for: .updateConfigs(mode: mode, tunEnabled: nil)
            )
            let data = try await apiService.data(for: .configs)
            let config = try MihomoAPIDecoder.runtimeConfig(from: data)
            guard config.mode == mode else {
                return .failure(OutboundModeRuntimeError.modeMismatch(
                    requested: mode,
                    effective: config.mode
                ))
            }
            return .success(config.mode)
        } catch {
            return .failure(error)
        }
    }

    private func applyTunToController(_ enabled: Bool) async -> Bool {
        do {
            _ = try await apiService.data(for: .updateConfigs(mode: nil, tunEnabled: enabled))
            let data = try await apiService.data(for: .configs)
            let config = try MihomoAPIDecoder.runtimeConfig(from: data)
            guard config.tunEnabled == enabled else {
                throw TunRuntimeError.settingNotApplied(enabled)
            }
            isTunEnabled = config.tunEnabled
            stagedTunEnabled = nil
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func synchronizeConfiguration(from url: URL) {
        do {
            let settings = try MihomoConfigurationInspector.inspect(url: url)
            httpPort = settings.httpPort
            socksPort = settings.socksPort
            selectedMode = settings.mode
            confirmedOutboundMode = settings.mode
            isTunEnabled = settings.tunEnabled
            controllerURL = URL(string: "http://\(settings.controllerHost):\(settings.controllerPort)")!
            controllerSecret = settings.secret
            apiService = MihomoAPIService(
                requestBuilder: MihomoAPIRequest(baseURL: controllerURL, secret: controllerSecret),
                session: apiService.session
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyPreparedRuntimeConfiguration(_ prepared: PreparedRuntimeConfiguration) {
        configPath = prepared.configURL.path
        httpPort = prepared.mixedPort
        socksPort = prepared.mixedPort
        controllerURL = prepared.controllerURL
        controllerSecret = prepared.controllerSecret
        apiService = MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: controllerURL, secret: controllerSecret),
            session: apiService.session
        )
        do {
            let settings = try MihomoConfigurationInspector.inspect(url: prepared.configURL)
            selectedMode = stagedOutboundMode ?? settings.mode
            confirmedOutboundMode = settings.mode
            isTunEnabled = stagedTunEnabled ?? settings.tunEnabled
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func ensureControllerAvailable(configPath: String) async -> Bool {
        if coreService.isProcessRunning,
           (try? await apiService.data(for: .version)) != nil {
            coreService.markRunning()
            coreStatus = coreService.status
            isCoreRunning = true
            return true
        }

        if coreService.isProcessRunning {
            await coreService.stop(userInitiated: false)
        }

        runtimeGeneration += 1

        do {
            let sourceURL: URL
            if let selectedManagedProfile {
                sourceURL = selectedManagedProfile.managedConfigURL
            } else {
                sourceURL = URL(fileURLWithPath: configPath)
            }
            let prepared = try runtimeConfigurationPreparer.prepare(
                sourceURL: sourceURL,
                runtimeDirectoryURL: profileRepository.runtimeDirectoryURL,
                routingOverrides: routingOverrides
            )
            applyPreparedRuntimeConfiguration(prepared)
        } catch {
            handleCoreFailure(error.localizedDescription)
            return false
        }

        await coreService.start(
            configPath: self.configPath,
            runtimeDirectoryURL: profileRepository.runtimeDirectoryURL
        )
        coreStatus = coreService.status
        guard coreStatus == .starting else {
            lastErrorMessage = coreStatus.failureMessage ?? "Mihomo could not start."
            isCoreRunning = false
            return false
        }

        guard await waitForController() else {
            let failure = coreService.status.failureMessage
                ?? coreService.recentOutput
                    .split(whereSeparator: \.isNewline)
                    .last
                    .map(String.init)
                ?? "Mihomo controller did not become ready at \(controllerURL.absoluteString)."
            await coreService.stop(userInitiated: false)
            coreStatus = .failed(failure)
            isStarted = false
            isCoreRunning = false
            lastErrorMessage = failure
            return false
        }

        coreService.markRunning()
        coreStatus = coreService.status
        isCoreRunning = true
        isStarted = false
        await restoreSavedProxySelections()
        guard coreService.isProcessRunning else {
            handleCoreFailure(coreService.status.failureMessage ?? "Mihomo exited unexpectedly.")
            return false
        }
        lastErrorMessage = nil
        return true
    }

    private func restartRuntimeForRoutingChangesIfNeeded() async throws {
        let wasStarted = isStarted
        let wasControllerRunning = isCoreRunning
        let activeMode = selectedMode
        guard wasControllerRunning else {
            return
        }
        if wasStarted {
            stagedOutboundMode = activeMode
            await stopRuntime(userInitiated: true)
            if !(await startRuntime(configPath: configPath)) {
                throw RoutingRuntimeError.restartFailed(
                    lastErrorMessage ?? "Mihomo did not restart with the new routing rules."
                )
            }
        } else {
            await stopControllerOnly(userInitiated: true)
            guard await ensureControllerAvailable(configPath: configPath) else {
                throw RoutingRuntimeError.restartFailed(
                    lastErrorMessage ?? "Mihomo controller did not restart with the new routing rules."
                )
            }
            if confirmedOutboundMode != activeMode,
               !(await applyOutboundModeToController(activeMode)) {
                throw RoutingRuntimeError.restartFailed(
                    lastErrorMessage ?? "Mihomo did not restore the active outbound mode."
                )
            }
            await fetchProxies()
        }
    }

    private func restoreSavedProxySelections() async {
        guard let profileID = selectedManagedProfileID,
              let selections = try? proxySelectionRepository.selections(profileID: profileID) else {
            return
        }
        for (selector, node) in selections {
            _ = try? await apiService.data(for: .changeProxy(group: selector, proxy: node))
        }
    }

    private func stopRuntime(userInitiated: Bool) async {
        runtimeGeneration += 1
        stagedOutboundMode = stagedOutboundMode ?? confirmedOutboundMode
        stagedTunEnabled = isTunEnabled
        stopTrafficStream()
        restorePreviousSystemProxy()
        await coreService.stop(userInitiated: userInitiated)
        coreStatus = coreService.status
        isStarted = false
        isCoreRunning = false
        isSystemProxyEnabled = false
        runtimeTickCount = 0
        latestUploadBytesPerSecond = 0
        latestDownloadBytesPerSecond = 0
        uploadSpeedText = "0B/s"
        downloadSpeedText = "0B/s"
        speedSamples = Array(repeating: 0, count: 28)
        await refreshNetworkIdentity()
    }

    private func stopControllerOnly(userInitiated: Bool) async {
        runtimeGeneration += 1
        stopTrafficStream()
        await coreService.stop(userInitiated: userInitiated)
        coreStatus = coreService.status
        isStarted = false
        isCoreRunning = false
        runtimeTickCount = 0
    }

    private func restorePreviousSystemProxy() {
        guard let previousSystemProxySnapshot else {
            isSystemProxyEnabled = false
            return
        }
        do {
            try systemProxyService.apply(
                .restore(service: networkService, snapshot: previousSystemProxySnapshot)
            )
            self.previousSystemProxySnapshot = nil
            isSystemProxyEnabled = false
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func waitForController() async -> Bool {
        for _ in 0..<60 {
            guard coreService.isProcessRunning else {
                coreStatus = coreService.status
                return false
            }
            if (try? await apiService.data(for: .version)) != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}

private enum OutboundModeRuntimeError: Error, LocalizedError {
    case modeMismatch(requested: OutboundMode, effective: OutboundMode)

    var errorDescription: String? {
        switch self {
        case let .modeMismatch(requested, effective):
            "Mihomo kept \(effective.title) mode instead of \(requested.title)."
        }
    }
}

private enum TunRuntimeError: Error, LocalizedError {
    case settingNotApplied(Bool)

    var errorDescription: String? {
        switch self {
        case let .settingNotApplied(enabled):
            "Mihomo did not \(enabled ? "enable" : "disable") TUN."
        }
    }
}
