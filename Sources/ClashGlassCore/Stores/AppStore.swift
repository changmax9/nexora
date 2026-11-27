import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class AppStore {
    public static let shared = AppStore()
    public let websiteComparison: WebsiteComparisonStore
    private let userDefaults: UserDefaults
    private let coreService: MihomoCoreService
    private var apiService: MihomoAPIService
    private let systemProxyService: SystemProxyService
    private let systemProxyRecoveryRepository: SystemProxyRecoveryRepository
    private let profileRepository: ManagedProfileRepository
    private let runtimeConfigurationPreparer: RuntimeConfigurationPreparer
    private let networkIdentityService: NetworkIdentityService
    private let networkPortProbe: @Sendable ([NetworkPortTarget]) async -> [NetworkPortCheck]
    private let networkDNSProbe: @Sendable ([NetworkDNSTarget]) async -> [NetworkDNSCheck]
    private let networkEndpointProbe: @Sendable ([NetworkEndpointTarget]) async -> [NetworkEndpointCheck]
    private let diagnosticExplanationService: DiagnosticExplanationService
    private let proxySelectionRepository: ProxySelectionRepository
    private let routingOverrideRepository: RoutingOverrideRepository
    private let announcementService: AnnouncementService
    private let announcementDismissalStore: AnnouncementDismissalStore
    private let appVersionProvider: @Sendable () -> String?
    private let nowProvider: @Sendable () -> Date
    @ObservationIgnored private var lastSuccessfulAnnouncementFetch: Date?
    @ObservationIgnored private var isFetchingAnnouncement = false
    @ObservationIgnored private var fetchedAnnouncement: Announcement?
    @ObservationIgnored private var announcementBoundaryTask: Task<Void, Never>?
    private let announcementRefreshCooldown: TimeInterval = 1800
    private var previousSystemProxySnapshot: SystemProxySnapshot?
    private var previousSystemProxyService: String?
    private var managedSystemProxySnapshot: SystemProxySnapshot?
    private var runtimeTickCount = 0
    @ObservationIgnored private var runtimeMonitorTask: Task<Void, Never>?
    private let automaticallyMonitorsRuntime: Bool
    private var isRuntimeTickInProgress = false
    private var consecutiveControllerFailures = 0
    private var lastAutomaticRecovery: ContinuousClock.Instant?
    private var lastProxyRestoreAttempt: ContinuousClock.Instant?
    private var trafficStreamTask: Task<Void, Never>?
    private var latestUploadBytesPerSecond = 0
    private var latestDownloadBytesPerSecond = 0
    private var confirmedOutboundMode: OutboundMode = .rule
    private var isApplyingOutboundMode = false
    private var pendingOutboundMode: OutboundMode?
    @ObservationIgnored private var runtimeTransitionWaiters: [CheckedContinuation<Void, Never>] = []
    private var runtimeGeneration = 0 {
        didSet { invalidateNetworkDiagnosis() }
    }
    private var networkIdentityGeneration = 0
    private(set) var isRefreshingNetworkIdentity = false
    public private(set) var isRuntimeTransitioning = false
    public var selectedSection: AppSection = .dashboard
    public var isCoreRunning = false { didSet { if oldValue != isCoreRunning { invalidateNetworkDiagnosis() } } }
    public var isStarted = false { didSet { if oldValue != isStarted { invalidateNetworkDiagnosis() } } }
    public var coreStatus: CoreRuntimeStatus = .stopped
    public var isSystemProxyEnabled = false { didSet { if oldValue != isSystemProxyEnabled { invalidateNetworkDiagnosis() } } }
    public var isTunEnabled = false { didSet { if oldValue != isTunEnabled { invalidateNetworkDiagnosis() } } }
    public var proxyHost = "127.0.0.1" { didSet { if oldValue != proxyHost { invalidateNetworkDiagnosis() } } }
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
            if oldValue != language {
                cancelDiagnosticExplanation()
                diagnosticExplanationDidFallback = false
                if let diagnosticExplanationContext {
                    diagnosticExplanation = diagnosticExplanationService.ruleExplanation(
                        context: diagnosticExplanationContext, language: language
                    )
                } else {
                    diagnosticExplanation = nil
                    diagnosticExplanationDate = nil
                    isDiagnosticExplanationStale = false
                }
            }
        }
    }
    public var reduceMotion = false {
        didSet {
            userDefaults.set(reduceMotion, forKey: "reduceMotion")
        }
    }
    private var blurStrengthStorage = GlassAppearance.defaultBlurStrength
    public var blurStrength: Double {
        get { blurStrengthStorage }
        set {
            blurStrengthStorage = GlassAppearance.normalized(newValue)
            userDefaults.set(blurStrengthStorage, forKey: "glassBlurStrength")
        }
    }

    public var glassAppearance: GlassAppearance {
        GlassAppearance(blurStrength: blurStrength)
    }

    public func resetGlassAppearance() {
        blurStrength = GlassAppearance.defaultBlurStrength
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
    public var httpPort = 7890 { didSet { if oldValue != httpPort { invalidateNetworkDiagnosis() } } }
    public var socksPort = 7891 { didSet { if oldValue != socksPort { invalidateNetworkDiagnosis() } } }
    public var selectedMode: OutboundMode = .rule { didSet { if oldValue != selectedMode { invalidateNetworkDiagnosis() } } }
    public private(set) var stagedOutboundMode: OutboundMode?
    public private(set) var stagedTunEnabled: Bool?
    public var selectedProfile = "No Profile"
    public var configPath = "\(NSHomeDirectory())/.config/clash/config.yaml"
    public private(set) var managedProfiles: [ManagedProfile] = []
    public private(set) var isRefreshingProfileTrafficUsage = false
    public private(set) var profileTrafficRefreshFailures: Set<ManagedProfile.ID> = []
    public private(set) var selectedManagedProfileID: ManagedProfile.ID?
    var routingOverrides: [RoutingOverride] = []
    private var profileStaticRoutingTargets: [RoutingProxyTarget] = []

    var availableRoutingProxyTargets: [RoutingProxyTarget] {
        RoutingProxyTargetCatalog.mergedTargets(
            staticTargets: profileStaticRoutingTargets,
            liveGroups: selectedProfileProxyGroups
        )
    }
    public private(set) var controllerURL = URL(string: "http://127.0.0.1:9090")!
    public private(set) var controllerSecret: String?
    public var externalIP = "Detecting..." { didSet { if oldValue != externalIP { invalidateNetworkDiagnosis() } } }
    public var networkCountryCode = ""
    public var networkCountryName = ""
    public var networkEgressKind: NetworkEgressKind = .detecting {
        didSet {
            if networkEgressKind != oldValue { invalidateNetworkDiagnosis() }
        }
    }
    public private(set) var networkDiagnosticReport = NetworkDiagnosticReport.placeholder
    public private(set) var networkDiagnosticReportDate: Date?
    public private(set) var diagnosticExplanation: DiagnosticExplanation?
    public private(set) var diagnosticExplanationDate: Date?
    public private(set) var isDiagnosticExplanationStale = false
    public private(set) var diagnosticModelAvailability: DiagnosticModelAvailability = .unavailable
    public private(set) var isExplainingDiagnosis = false
    public private(set) var diagnosticExplanationDidFallback = false
    private var diagnosticExplanationContext: DiagnosticExplanationContext?
    private var diagnosticExplanationGeneration = 0
    @ObservationIgnored private var diagnosticExplanationTask: Task<Void, Never>?
    private var networkDiagnosticRevision = 0
    public private(set) var isRunningNetworkDiagnosis = false
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
    @ObservationIgnored public var onCheckForUpdatesRequested: (@MainActor () -> Void)?
    @ObservationIgnored public var onInstallUpdateRequested: (@MainActor () -> Void)?
    public private(set) var isCheckingForUpdates = false
    public var manualUpdateCheckResult: ManualUpdateCheckResult?
    public private(set) var activeAnnouncement: Announcement?
    public private(set) var latestAnnouncement: Announcement?
    // Proxy cleanup failures must survive successful traffic/config responses.
    public private(set) var systemProxyErrorMessage: String? {
        didSet {
            if systemProxyErrorMessage != oldValue {
                acknowledgedSystemProxyError = nil
                invalidateNetworkDiagnosis()
            }
        }
    }
    private var acknowledgedSystemProxyError: String?
    private var transientErrorMessage: String?
    public var lastErrorMessage: String? {
        get { systemProxyErrorMessage ?? transientErrorMessage }
        set { transientErrorMessage = newValue }
    }
    public var errorAlertMessage: String? {
        if let systemProxyErrorMessage, systemProxyErrorMessage != acknowledgedSystemProxyError {
            return systemProxyErrorMessage
        }
        return transientErrorMessage
    }

    public func dismissErrorAlert() {
        acknowledgedSystemProxyError = systemProxyErrorMessage
        transientErrorMessage = nil
    }

    public func requestManualUpdateCheck() {
        guard !isCheckingForUpdates else { return }
        manualUpdateCheckResult = nil
        guard let onCheckForUpdatesRequested else {
            manualUpdateCheckResult = .failed(message: text(.updateCheckUnavailable))
            return
        }
        isCheckingForUpdates = true
        onCheckForUpdatesRequested()
    }

    public func finishManualUpdateCheck(_ result: ManualUpdateCheckResult) {
        isCheckingForUpdates = false
        manualUpdateCheckResult = result
    }

    public func cancelManualUpdateCheck() {
        isCheckingForUpdates = false
    }

    public func dismissManualUpdateCheckResult() {
        manualUpdateCheckResult = nil
    }

    public func proceedWithSparkleUpdate() {
        manualUpdateCheckResult = nil
        onInstallUpdateRequested?()
    }

    public func checkForAnnouncement(force: Bool = false) async {
        guard !isFetchingAnnouncement else { return }
        let now = nowProvider()
        if !force,
           let lastFetch = lastSuccessfulAnnouncementFetch,
           now.timeIntervalSince(lastFetch) < announcementRefreshCooldown {
            updateAnnouncementPresentation(at: now)
            return
        }
        isFetchingAnnouncement = true
        defer { isFetchingAnnouncement = false }
        do {
            fetchedAnnouncement = try await announcementService.fetchLatestAnnouncement()
            lastSuccessfulAnnouncementFetch = nowProvider()
        } catch {
            // Offline, the last successful response still follows its local display window.
        }
        updateAnnouncementPresentation(at: nowProvider())
    }

    private func updateAnnouncementPresentation(at now: Date) {
        announcementBoundaryTask?.cancel()
        announcementBoundaryTask = nil
        if let item = fetchedAnnouncement, item.isActive(at: now, appVersion: appVersionProvider()) {
            latestAnnouncement = item
            if activeAnnouncement?.id == item.id || announcementDismissalStore.shouldPresent(item, at: now) {
                activeAnnouncement = item
            } else {
                activeAnnouncement = nil
            }
        } else {
            latestAnnouncement = nil
            activeAnnouncement = nil
        }

        let nextBoundary = [fetchedAnnouncement?.startsAt, fetchedAnnouncement?.expiresAt]
            .compactMap { $0 }.filter { $0 > now }.min()
        if let nextBoundary {
            announcementBoundaryTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(nextBoundary.timeIntervalSince(now)))
                } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.updateAnnouncementPresentation(at: self.nowProvider())
            }
        }
    }

    deinit {
        announcementBoundaryTask?.cancel()
    }

    public func dismissActiveAnnouncement() {
        guard let announcement = activeAnnouncement else { return }
        announcementDismissalStore.markDismissed(announcement, at: nowProvider())
        activeAnnouncement = nil
    }

    public func reopenLatestAnnouncement() {
        guard let latest = latestAnnouncement,
              latest.isActive(at: nowProvider(), appVersion: appVersionProvider()) else {
            return
        }
        activeAnnouncement = latest
    }
    public private(set) var profileValidationStates: [ManagedProfile.ID: ProfileValidationState] = [:]
    var isLatencyTesting = false
    var latencyTestProgress = LatencyTestProgress(completed: 0, total: 0)
    public var speedSamples: [Double] = Array(repeating: 0, count: 28)

    var proxyGroups: [ProxyGroup] = [] {
        didSet { proxySnapshotProfileID = selectedManagedProfileID }
    }
    private var proxySnapshotProfileID: ManagedProfile.ID?
    var selectedProfileProxyGroups: [ProxyGroup] {
        proxySnapshotProfileID == selectedManagedProfileID ? proxyGroups : []
    }
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
        diagnosticExplanationService: DiagnosticExplanationService = DiagnosticExplanationService(),
        websiteComparisonService: WebsiteComparisonService = WebsiteComparisonService(),
        proxySelectionRepository: ProxySelectionRepository? = nil,
        announcementService: AnnouncementService = AnnouncementService(),
        appVersionProvider: @escaping @Sendable () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        userDefaults: UserDefaults = .standard,
        automaticallyMonitorsRuntime: Bool = true
    ) {
        self.automaticallyMonitorsRuntime = automaticallyMonitorsRuntime
        self.userDefaults = userDefaults
        self.coreService = coreService
        self.apiService = apiService
        self.systemProxyService = systemProxyService
        systemProxyRecoveryRepository = SystemProxyRecoveryRepository(rootURL: profileRepository.rootURL)
        self.profileRepository = profileRepository
        self.runtimeConfigurationPreparer = runtimeConfigurationPreparer
        self.networkIdentityService = networkIdentityService
        self.networkPortProbe = networkPortProbe
        self.networkDNSProbe = networkDNSProbe
        self.networkEndpointProbe = networkEndpointProbe
        self.diagnosticExplanationService = diagnosticExplanationService
        websiteComparison = WebsiteComparisonStore(service: websiteComparisonService)
        self.proxySelectionRepository = proxySelectionRepository
            ?? ProxySelectionRepository(rootURL: profileRepository.rootURL)
        self.announcementService = announcementService
        self.announcementDismissalStore = AnnouncementDismissalStore(userDefaults: userDefaults)
        self.appVersionProvider = appVersionProvider
        self.nowProvider = nowProvider
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
        if let value = userDefaults.object(forKey: "glassBlurStrength") as? Double {
            blurStrengthStorage = GlassAppearance.normalized(value)
        }
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
        do {
            _ = try await importManagedProfileFile(from: sourceURL)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func importManagedProfile(
        fromRemoteURL sourceURL: URL,
        downloader: ManagedProfileDownloader = ManagedProfileDownloader()
    ) async throws -> Bool {
        let download = try await downloader.download(from: sourceURL)
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("config.yaml")
        try download.data.write(to: fileURL, options: .atomic)
        return try await importManagedProfileFile(
            from: fileURL, name: download.name,
            subscriptionURL: sourceURL, trafficUsage: download.trafficUsage
        )
    }

    private func importManagedProfileFile(
        from sourceURL: URL, name: String? = nil,
        subscriptionURL: URL? = nil, trafficUsage: ProfileTrafficUsage? = nil
    ) async throws -> Bool {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        try Task.checkCancellation()
        let profile = try await profileRepository.importProfile(
            from: sourceURL, name: name,
            subscriptionURL: subscriptionURL, trafficUsage: trafficUsage
        ) { stagedURL in
            await self.validateProfileConfiguration(at: stagedURL)
        }
        let activated = await activateManagedProfile(profile)
        profileValidationStates[profile.id] = .valid()
        return activated
    }

    public func refreshManagedProfileTrafficUsage(
        downloader: ManagedProfileDownloader = ManagedProfileDownloader()
    ) async {
        guard !isRefreshingProfileTrafficUsage else { return }
        isRefreshingProfileTrafficUsage = true
        defer { isRefreshingProfileTrafficUsage = false }
        for profile in managedProfiles {
            guard !Task.isCancelled else { return }
            guard let url = profile.subscriptionURL else { continue }
            do {
                let download = try await downloader.download(from: url)
                try Task.checkCancellation()
                guard let index = managedProfiles.firstIndex(where: { $0.id == profile.id }) else { continue }
                guard let usage = download.trafficUsage else {
                    profileTrafficRefreshFailures.insert(profile.id)
                    continue
                }
                // Refresh quota metadata only; the saved YAML and active runtime stay intact.
                try profileRepository.updateTrafficUsage(usage, for: profile.id)
                managedProfiles[index].trafficUsage = usage
                profileTrafficRefreshFailures.remove(profile.id)
            } catch is CancellationError {
                return
            } catch {
                // Keep the last provider snapshot when offline or when a profile was deleted.
                guard !Task.isCancelled else { return }
                if managedProfiles.contains(where: { $0.id == profile.id }) {
                    profileTrafficRefreshFailures.insert(profile.id)
                }
            }
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
                    guard await stopRuntime(userInitiated: true) else { return }
                } else {
                    guard await stopControllerOnly(userInitiated: true) else { return }
                }
            }
            try profileRepository.remove(id)
            try? routingOverrideRepository.removeProfile(id)
            profileValidationStates.removeValue(forKey: id)
            profileTrafficRefreshFailures.remove(id)
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
        switch await validateProfileConfiguration(at: profile.managedConfigURL) {
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
            switch await validateProfileConfiguration(at: profile.managedConfigURL) {
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

    private func validateProfileConfiguration(at sourceURL: URL) async -> ConfigValidationResult {
        do {
            let yaml = try String(contentsOf: sourceURL, encoding: .utf8)
            guard let compatibleYAML = try runtimeConfigurationPreparer.validationConfiguration(yaml: yaml) else {
                return await coreService.validateConfig(path: sourceURL.path)
            }
            // Validate compatibility edits without changing the imported source.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NexoraValidation-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let validationURL = directory.appendingPathComponent("config.yaml")
            try compatibleYAML.write(to: validationURL, atomically: true, encoding: .utf8)
            // Keep the existing validation home/working-directory behavior (no -d).
            return await coreService.validateConfig(path: validationURL.path)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func addRoutingOverride(
        input: String,
        policy: RoutingPolicy,
        proxyName: String? = nil
    ) async {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        guard let profileID = selectedManagedProfileID else {
            lastErrorMessage = "Select a managed profile before adding routing rules."
            return
        }
        do {
            let domain = try RoutingInputNormalizer.domain(from: input)
            let normalizedProxyName: String?
            switch policy {
            case .vpn:
                normalizedProxyName = nil
                if let profile = selectedManagedProfile {
                    let yaml = try String(
                        contentsOf: profile.managedConfigURL,
                        encoding: .utf8
                    )
                    guard RoutingVPNTargetResolver.target(from: yaml) != nil else {
                        throw RuntimeConfigurationError.missingVPNPolicyGroup
                    }
                }
            case .customNode:
                let trimmed = proxyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmed.isEmpty else {
                    throw RoutingInputError.missingProxyNode
                }
                normalizedProxyName = trimmed
            case .direct:
                normalizedProxyName = nil
            }
            let candidateOverrides = routingOverrides.filter { $0.domain != domain }
                + [RoutingOverride(domain: domain, policy: policy, proxyName: normalizedProxyName)]
            try await validateRoutingChanges(candidateOverrides)
            try routingOverrideRepository.upsert(
                domain: domain,
                policy: policy,
                proxyName: normalizedProxyName,
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
            try await validateRoutingChanges(routingOverrides.filter { $0.domain != domain })
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

    /// Siri uses explicit desired states and the same transition queue as the UI.
    public func setConnectionEnabledForAutomation(_ enabled: Bool) async throws {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        try Task.checkCancellation()
        transientErrorMessage = nil
        if enabled {
            if !isStarted || !coreService.isProcessRunning {
                guard await startRuntime(configPath: configPath) else {
                    throw automationFailure("Nexora could not connect.")
                }
            }
            if !isSystemProxyEnabled, !isTunEnabled {
                await applySystemProxy(enabled: true, service: networkService)
            }
            guard isStarted, coreService.isProcessRunning, systemProxyErrorMessage == nil else {
                throw automationFailure("Nexora could not connect.")
            }
        } else {
            if isStarted {
                await stopRuntime(userInitiated: true)
                guard !isStarted else { throw automationFailure("The system proxy could not be restored.") }
            } else if isCoreRunning {
                guard await stopControllerOnly(userInitiated: true) else {
                    throw automationFailure("The system proxy could not be restored.")
                }
            }
            guard restorePreviousSystemProxy() else {
                throw automationFailure("The system proxy could not be restored.")
            }
        }
    }

    public func setTUNEnabledForAutomation(_ enabled: Bool) async throws {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        try Task.checkCancellation()
        transientErrorMessage = nil
        if !enabled, !isStarted, coreService.isPrivilegedRunning {
            guard await stopControllerOnly(userInitiated: true) else {
                throw automationFailure("The system proxy could not be restored.")
            }
        }
        await setTunDuringTransition(enabled)
        guard isTunEnabled == enabled, transientErrorMessage == nil,
              systemProxyErrorMessage == nil else {
            throw automationFailure("Nexora could not change TUN mode.")
        }
    }

    /// Parameter resolution is read-only: it never launches a core, enables
    /// proxy settings, or requests TUN privileges just to populate Siri's list.
    public func automationProxyNodes() async throws -> [AutomationProxyNode] {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        try Task.checkCancellation()
        if isCoreRunning, coreService.isProcessRunning {
            await fetchProxies()
        }
        if !selectedProfileProxyGroups.isEmpty { return currentAutomationProxyNodes() }
        guard let profileID = selectedManagedProfileID?.uuidString,
              let data = try? Data(contentsOf: automationCatalogURL),
              let nodes = try? JSONDecoder().decode([AutomationProxyNode].self, from: data) else { return [] }
        return nodes.filter { $0.profileID == profileID }
    }

    public func selectProxyForAutomation(id: String) async throws {
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        try Task.checkCancellation()
        // Check before launching anything: an old shortcut must not alter a
        // newly selected profile, even if it happens to contain the same name.
        let knownNodes: [AutomationProxyNode]
        if !selectedProfileProxyGroups.isEmpty {
            knownNodes = currentAutomationProxyNodes()
        } else if let data = try? Data(contentsOf: automationCatalogURL),
                  let nodes = try? JSONDecoder().decode([AutomationProxyNode].self, from: data) {
            knownNodes = nodes.filter { $0.profileID == selectedManagedProfileID?.uuidString }
        } else { knownNodes = [] }
        guard knownNodes.contains(where: { $0.id == id }) else { throw AutomationControlError.nodeUnavailable }
        if !isStarted, stagedTunEnabled ?? isTunEnabled {
            throw AutomationControlError.operationFailed(
                "Connect Nexora before selecting a node while TUN is enabled."
            )
        }
        transientErrorMessage = nil
        guard await ensureControllerAvailable(configPath: configPath) else {
            throw automationFailure("Nexora could not load the selected profile.")
        }
        await fetchProxies()
        guard let node = currentAutomationProxyNodes().first(where: { $0.id == id }) else {
            throw AutomationControlError.nodeUnavailable
        }
        try await selectProxyDuringTransition(groupName: node.groupName, nodeName: node.name).get()
    }

    private func automationFailure(_ fallback: String) -> AutomationControlError {
        .operationFailed(lastErrorMessage ?? fallback)
    }

    private var automationCatalogURL: URL {
        profileRepository.rootURL.appendingPathComponent("automation-nodes.json")
    }

    private func currentAutomationProxyNodes() -> [AutomationProxyNode] {
        guard let profileID = selectedManagedProfileID?.uuidString else { return [] }
        let groups = MenuBarProxyResolver.selectors(in: selectedProfileProxyGroups)
        var nodes: [AutomationProxyNode] = []
        for group in groups {
            for node in group.nodes where !node.isGroup {
                nodes.append(AutomationProxyNode(profileID: profileID, groupName: group.name, name: node.name))
            }
        }
        return nodes.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.groupName < rhs.groupName : lhs.name < rhs.name
        }
    }

    private func saveAutomationProxyCatalog() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(currentAutomationProxyNodes()) else { return }
        guard (try? Data(contentsOf: automationCatalogURL)) != data else { return }
        do {
            try data.write(to: automationCatalogURL, options: .atomic)
            NotificationCenter.default.post(name: AutomationProxyNode.catalogDidChange, object: nil)
        } catch {
            // A read-only/full disk must not break an otherwise working proxy.
        }
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
        guard isSystemProxyEnabled, systemProxyErrorMessage == nil else {
            let failure = lastErrorMessage ?? "Could not apply system proxy settings."
            await stopRuntime(userInitiated: false)
            lastErrorMessage = failure
            return false
        }
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
            guard await stopControllerOnly(userInitiated: true) else { return }
            guard await ensureControllerAvailable(configPath: configPath) else {
                return
            }
            if confirmedOutboundMode != activeMode {
                guard await applyOutboundModeToController(activeMode) else { return }
            }
            await fetchProxies()
        case .restartActiveRuntime:
            stagedOutboundMode = activeMode
            guard await stopRuntime(userInitiated: true) else { return }
            _ = await startRuntime(configPath: configPath)
        }
    }

    @discardableResult
    public func shutdownForApplicationTermination() -> Bool {
        guard restorePreviousSystemProxy() else { return false }
        websiteComparison.cancel()
        cancelDiagnosticExplanation()
        runtimeMonitorTask?.cancel()
        runtimeMonitorTask = nil
        stopTrafficStream()
        coreService.stopImmediately()
        coreStatus = coreService.status
        isStarted = false
        isCoreRunning = false
        return true
    }

    public func recoverSystemProxyAfterRelaunch() {
        guard !isStarted, !coreService.isProcessRunning else { return }
        restorePreviousSystemProxy()
    }

    public func resumeRuntimeAfterWake() async {
        guard !isRuntimeTransitioning, isCoreRunning || isStarted else { return }
        // Recreate a stream whose socket may have become stale during sleep.
        if isStarted { startTrafficStream() }
        runtimeTickCount = 9
        await runtimeTick()
    }

    public func toggleSystemProxy(service: String = "Wi-Fi") async {
        guard !isRuntimeTransitioning else { return }
        guard isStarted else {
            if previousSystemProxySnapshot != nil {
                restorePreviousSystemProxy()
                return
            }
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
        guard !isRuntimeTransitioning else { return }
        await beginRuntimeTransition()
        defer { endRuntimeTransition() }
        await setTunDuringTransition(enabled)
    }

    private func setTunDuringTransition(_ enabled: Bool) async {
        let previousValue = isTunEnabled
        if isStarted, coreService.supportsPrivilegedTUN, enabled != previousValue {
            if enabled {
                do { try coreService.authorizeTUN() }
                catch { lastErrorMessage = error.localizedDescription; return }
            }
            guard await stopRuntime(userInitiated: true) else { return }
            stagedTunEnabled = enabled
            isTunEnabled = enabled
            if !(await startRuntime(configPath: configPath)) {
                let failure = lastErrorMessage ?? "TUN could not start."
                guard await stopControllerOnly(userInitiated: true) else { return }
                stagedTunEnabled = previousValue
                isTunEnabled = previousValue
                _ = await startRuntime(configPath: configPath)
                lastErrorMessage = failure
            }
            return
        }
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
        await selectProxyDuringTransition(groupName: groupName, nodeName: nodeName)
    }

    @discardableResult
    private func selectProxyDuringTransition(groupName: String, nodeName: String) async -> Result<Void, Error> {
        guard await ensureControllerAvailable(configPath: configPath) else {
            return .failure(automationFailure("Nexora could not load the selected profile."))
        }
        let targetGroups = ProxySelectionResolver.targetGroups(
            selectedGroupName: groupName,
            nodeName: nodeName,
            groups: proxyGroups
        )
        guard !targetGroups.isEmpty else {
            lastErrorMessage = "This automatic group cannot be manually locked without a parent selector."
            return .failure(automationFailure("This node cannot be selected manually."))
        }
        do {
            for targetGroup in targetGroups {
                _ = try await apiService.data(
                    for: .changeProxy(group: targetGroup, proxy: nodeName)
                )
                invalidateNetworkDiagnosis()
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
            let confirmation = try await apiService.data(for: .proxies)
            let confirmedGroups = try MihomoAPIDecoder.proxyGroups(from: confirmation)
            guard targetGroups.allSatisfy({ target in
                confirmedGroups.first(where: { $0.name == target })?
                    .nodes.first(where: \.isSelected)?.name == nodeName
            }) else {
                throw AutomationControlError.operationFailed("Mihomo did not apply the requested node selection.")
            }
            lastErrorMessage = nil
            await fetchProxies()
            if isStarted {
                await refreshNetworkIdentity()
            }
            return .success(())
        } catch {
            let message = error.localizedDescription
            // A later failure (including closing old connections) cannot undo a
            // selector change already accepted by the controller.
            await fetchProxies()
            lastErrorMessage = message
            if isStarted { await refreshNetworkIdentity() }
            return .failure(error)
        }
    }

    public func delayTestAll() async {
        guard !isLatencyTesting, !Task.isCancelled else {
            return
        }
        isLatencyTesting = true
        defer { isLatencyTesting = false }
        await beginRuntimeTransition()
        let controllerAvailable = await ensureControllerAvailable(configPath: configPath)
        endRuntimeTransition()
        guard controllerAvailable, !Task.isCancelled else {
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
        func isCurrentTest() -> Bool {
            !Task.isCancelled && generation == runtimeGeneration
        }
        func publish(
            delays: [String: Int],
            completed names: Set<String>
        ) {
            guard isCurrentTest() else { return }
            completedNodeNames.formUnion(names)
            latencyTestProgress = LatencyTestProgress(
                completed: completedNodeNames.count,
                total: plan.nodeNames.count
            )
            successfulNodeNames.formUnion(delays.keys)
            if !delays.isEmpty {
                var updatedGroups = proxyGroups
                for groupIndex in updatedGroups.indices {
                    for nodeIndex in updatedGroups[groupIndex].nodes.indices {
                        let nodeName = updatedGroups[groupIndex].nodes[nodeIndex].name
                        if let latency = delays[nodeName] {
                            updatedGroups[groupIndex].nodes[nodeIndex].latency = latency
                        }
                    }
                }
                proxyGroups = updatedGroups
            }
        }

        for batchStart in stride(
            from: 0,
            to: plan.groupTests.count,
            by: LatencyTestPlan.maximumConcurrentGroupTests
        ) {
            guard isCurrentTest() else { return }
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
                    guard isCurrentTest() else {
                        taskGroup.cancelAll()
                        break
                    }
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
            guard isCurrentTest() else { return }
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
                            timeout: settings.timeoutMilliseconds,
                            provider: test.providerName
                        )
                        return (test.proxyName, latency)
                    }
                }
                for await (nodeName, latency) in taskGroup {
                    guard isCurrentTest() else {
                        taskGroup.cancelAll()
                        break
                    }
                    publish(
                        delays: latency.map { [nodeName: $0] } ?? [:],
                        completed: [nodeName]
                    )
                }
            }
        }
        guard isCurrentTest() else { return }
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
        guard !isRuntimeTickInProgress else { return }
        isRuntimeTickInProgress = true
        defer { isRuntimeTickInProgress = false }
        if !isStarted, previousSystemProxySnapshot != nil, systemProxyErrorMessage != nil {
            if lastProxyRestoreAttempt.map({ $0.duration(to: .now) >= .seconds(5) }) ?? true {
                restorePreviousSystemProxy()
            }
        }
        guard !isRuntimeTransitioning, isCoreRunning || isStarted else {
            return
        }
        guard coreService.isProcessRunning else {
            handleCoreFailure(coreService.status.failureMessage ?? "Mihomo exited unexpectedly.")
            return
        }
        let generation = runtimeGeneration
        runtimeTickCount += 1
        if runtimeTickCount.isMultiple(of: 10) {
            guard await checkControllerHealth(), generation == runtimeGeneration else { return }
        }
        guard isStarted else { return }
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
        let profileID = selectedManagedProfileID
        let service = apiService
        do {
            async let providerData = try? service.data(for: .proxyProviders)
            let data = try await service.data(for: .proxies)
            let providers = await providerData
            guard generation == runtimeGeneration, profileID == selectedManagedProfileID else { return }
            applyProxyResponse(data, providerData: providers, profileID: profileID)
        } catch {
            guard generation == runtimeGeneration, profileID == selectedManagedProfileID else { return }
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
        applyProxyResponse(data, profileID: selectedManagedProfileID)
    }

    func applyProxyResponse(_ data: Data, providerData: Data? = nil, profileID: ManagedProfile.ID?) {
        guard profileID == selectedManagedProfileID else { return }
        do {
            let measuredLatencies = Dictionary(
                selectedProfileProxyGroups
                    .flatMap(\.nodes)
                    .compactMap { node in
                        node.latency.map { (node.name, $0) }
                    },
                uniquingKeysWith: { current, _ in current }
            )
            var groups = try MihomoAPIDecoder.proxyGroups(from: data, providerData: providerData)
            for groupIndex in groups.indices {
                for nodeIndex in groups[groupIndex].nodes.indices {
                    let nodeName = groups[groupIndex].nodes[nodeIndex].name
                    groups[groupIndex].nodes[nodeIndex].latency = measuredLatencies[nodeName]
                        ?? groups[groupIndex].nodes[nodeIndex].latency
                }
            }
            proxyGroups = groups
            saveAutomationProxyCatalog()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func applyConnectionsResponse(_ data: Data) {
        do {
            let snapshot = try MihomoAPIDecoder.connectionsSnapshot(from: data)
            if connections != snapshot.entries {
                connections = snapshot.entries
            }
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
        let wasEnabled = isSystemProxyEnabled
        do {
            try loadSystemProxyRecoveryIfNeeded()
            if enabled, let previousSystemProxyService, previousSystemProxyService != service {
                guard restorePreviousSystemProxy() else { return }
            }
            if enabled, previousSystemProxySnapshot == nil {
                let snapshot = try systemProxyService.capture(service: service)
                    .removingProxy(host: proxyHost, httpPort: httpPort, socksPort: socksPort)
                let managed = SystemProxySnapshot.enabled(host: proxyHost, httpPort: httpPort, socksPort: socksPort)
                try systemProxyRecoveryRepository.save(.ownedByCurrentProcess(service: service, snapshot: snapshot, managedProxy: managed))
                previousSystemProxySnapshot = snapshot
                previousSystemProxyService = service
                managedSystemProxySnapshot = managed
            } else if enabled, let snapshot = previousSystemProxySnapshot {
                let managed = SystemProxySnapshot.enabled(host: proxyHost, httpPort: httpPort, socksPort: socksPort)
                try systemProxyRecoveryRepository.save(.ownedByCurrentProcess(service: service, snapshot: snapshot, managedProxy: managed))
                managedSystemProxySnapshot = managed
            }
            if !enabled {
                restorePreviousSystemProxy()
                return
            }
            let command = SystemProxyCommand.enable(
                service: service, host: proxyHost, httpPort: httpPort, socksPort: socksPort
            )
            try systemProxyService.apply(command)
            isSystemProxyEnabled = enabled
            systemProxyErrorMessage = nil
            lastErrorMessage = nil
        } catch {
            if enabled, previousSystemProxySnapshot != nil {
                restorePreviousSystemProxy()
            } else {
                isSystemProxyEnabled = wasEnabled
            }
            systemProxyErrorMessage = error.localizedDescription
        }
    }

    private func startRuntimeMonitorIfNeeded() {
        guard automaticallyMonitorsRuntime, runtimeMonitorTask == nil else { return }
        runtimeMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
                guard let self else { return }
                await self.runtimeTick()
            }
        }
    }

    private func checkControllerHealth() async -> Bool {
        let generation = runtimeGeneration
        do {
            _ = try await apiService.data(for: .version)
            guard generation == runtimeGeneration, !isRuntimeTransitioning, !Task.isCancelled else { return false }
            consecutiveControllerFailures = 0
            return true
        } catch {
            guard generation == runtimeGeneration, !isRuntimeTransitioning, !Task.isCancelled else { return false }
            consecutiveControllerFailures += 1
            guard consecutiveControllerFailures >= 3 else { return false }
            consecutiveControllerFailures = 0
            // One recovery per minute. Persistent faults release the system proxy
            // instead of trapping the whole machine in an endless restart loop.
            if let lastAutomaticRecovery, lastAutomaticRecovery.duration(to: .now) < .seconds(60) {
                await beginRuntimeTransition()
                defer { endRuntimeTransition() }
                let failure = "Mihomo controller is unresponsive after recovery. The connection was stopped to restore network access."
                guard await stopRuntime(userInitiated: false) else { return false }
                coreStatus = .failed(failure)
                lastErrorMessage = failure
                return false
            }
            lastAutomaticRecovery = .now
            await restartCore()
            return false
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
        guard !isRunningNetworkDiagnosis else { return }
        cancelDiagnosticExplanation()
        isRunningNetworkDiagnosis = true
        defer { isRunningNetworkDiagnosis = false }
        let generation = runtimeGeneration
        await refreshNetworkIdentity()
        let egress = networkEgressKind
        let revision = networkDiagnosticRevision
        let activeSystemTunnel = await networkIdentityService.hasActiveSystemTunnel()
        let targets = NetworkPortTarget.standard(
            httpPort: httpPort,
            socksPort: socksPort,
            controllerPort: controllerURL.port ?? 9090
        )
        async let portChecks = networkPortProbe(targets)
        async let dnsChecks = networkDNSProbe(NetworkDNSTarget.standard)
        async let endpointChecks = networkEndpointProbe(NetworkEndpointTarget.standard)
        let ports = await portChecks
        let dns = await dnsChecks
        let endpoints = await endpointChecks
        guard generation == runtimeGeneration, revision == networkDiagnosticRevision,
              egress == networkEgressKind, !Task.isCancelled else { return }
        networkPortChecks = ports
        networkDNSChecks = dns
        networkEndpointChecks = endpoints
        let snapshot = NetworkDiagnosticSnapshot(
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
                endpointChecks: networkEndpointChecks,
                coreProcessID: coreService.processIdentifier
        )
        networkDiagnosticReport = NetworkDiagnosticEngine.report(snapshot: snapshot)
        networkDiagnosticReportDate = Date()
        diagnosticExplanationDate = networkDiagnosticReportDate
        isDiagnosticExplanationStale = false
        let context = DiagnosticExplanationContext(
            snapshot: snapshot, hasSystemProxyError: systemProxyErrorMessage != nil
        )
        diagnosticExplanationContext = context
        diagnosticExplanation = diagnosticExplanationService.ruleExplanation(context: context, language: language)
        diagnosticExplanationDidFallback = false
        refreshDiagnosticModelAvailability()
    }

    public func compareWebsite() async {
        guard !websiteComparison.isRunning else { return }
        let revision = networkDiagnosticRevision
        let systemTunnel = await networkIdentityService.hasActiveSystemTunnel()
        guard revision == networkDiagnosticRevision, !Task.isCancelled else { return }
        await websiteComparison.run(context: .init(
            proxy: isCoreRunning || isStarted ? .init(host: proxyHost, port: httpPort) : nil,
            mode: selectedMode, hasSystemTunnel: isTunEnabled || systemTunnel
        ))
    }

    public func refreshDiagnosticModelAvailability() {
        diagnosticModelAvailability = diagnosticExplanationService.availability()
    }

    public func cancelDiagnosticExplanation() {
        diagnosticExplanationGeneration += 1
        diagnosticExplanationTask?.cancel()
        diagnosticExplanationTask = nil
        isExplainingDiagnosis = false
    }

    public func explainNetworkDiagnosis() async {
        guard !isExplainingDiagnosis, !isRunningNetworkDiagnosis,
              networkDiagnosticReportDate != nil, let context = diagnosticExplanationContext else { return }
        refreshDiagnosticModelAvailability()
        diagnosticExplanationGeneration += 1
        let request = diagnosticExplanationGeneration
        let revision = networkDiagnosticRevision
        let requestedLanguage = language
        let service = diagnosticExplanationService
        isExplainingDiagnosis = true
        diagnosticExplanationDidFallback = false
        let task = Task { [weak self] in
            defer {
                if let self, self.diagnosticExplanationGeneration == request {
                    self.isExplainingDiagnosis = false
                    self.diagnosticExplanationTask = nil
                }
            }
            do {
                let explanation = try await service.explain(context: context, language: requestedLanguage)
                try Task.checkCancellation()
                guard let self, self.diagnosticExplanationGeneration == request,
                      self.networkDiagnosticRevision == revision, self.language == requestedLanguage else { return }
                self.diagnosticExplanation = explanation
                self.diagnosticExplanationDidFallback = explanation.source == .rules
            } catch {
                guard !Task.isCancelled, let self, self.diagnosticExplanationGeneration == request,
                      self.networkDiagnosticRevision == revision, self.language == requestedLanguage else { return }
                self.diagnosticExplanation = service.ruleExplanation(context: context, language: requestedLanguage)
                self.diagnosticExplanationDidFallback = true
            }
        }
        diagnosticExplanationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func invalidateNetworkDiagnosis() {
        websiteComparison.invalidate()
        cancelDiagnosticExplanation()
        diagnosticExplanationContext = nil
        isDiagnosticExplanationStale = diagnosticExplanation != nil
        diagnosticExplanationDidFallback = false
        networkDiagnosticRevision += 1
        networkDiagnosticReport = .placeholder
        networkDiagnosticReportDate = nil
        networkPortChecks = []
        networkDNSChecks = []
        networkEndpointChecks = []
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
        let generation = runtimeGeneration
        trafficStreamTask = Task { [weak self] in
            var retryMilliseconds = 350
            while !Task.isCancelled, self?.isStarted == true {
                do {
                    for try await data in service.lineDataStream(for: .traffic) {
                        guard !Task.isCancelled, let self, self.isStarted,
                              generation == self.runtimeGeneration else {
                            return
                        }
                        self.applyLiveTrafficResponse(data)
                        retryMilliseconds = 350
                    }
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                }
                // An empty successful response also needs backoff, or EOF creates a tight loop.
                guard !Task.isCancelled, self?.isStarted == true,
                      self?.runtimeGeneration == generation else { return }
                do { try await Task.sleep(for: .milliseconds(retryMilliseconds)) }
                catch { return }
                retryMilliseconds = min(retryMilliseconds * 2, 5_000)
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
                guard await stopRuntime(userInitiated: true) else { return false }
            } else if wasCoreRunning {
                guard await stopControllerOnly(userInitiated: true) else { return false }
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
            profileStaticRoutingTargets = []
            return
        }
        if let profile = selectedManagedProfile,
           let yaml = try? String(contentsOf: profile.managedConfigURL, encoding: .utf8) {
            profileStaticRoutingTargets = RoutingProxyTargetCatalog.staticTargets(fromYAML: yaml)
        } else {
            profileStaticRoutingTargets = []
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
                if enabled, let detail = await coreService.tunStartupFailure() {
                    throw NSError(domain: "Nexora.TUN", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
                }
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
            var controllerComponents = URLComponents()
            controllerComponents.scheme = "http"
            controllerComponents.host = settings.controllerHost.contains(":")
                ? "[\(settings.controllerHost)]" : settings.controllerHost
            controllerComponents.port = settings.controllerPort
            guard let configurationControllerURL = controllerComponents.url else {
                throw ManagedProfileError.validationFailed("Invalid controller address in the selected configuration.")
            }
            controllerURL = configurationControllerURL
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
        do {
            try loadSystemProxyRecoveryIfNeeded()
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
        if !coreService.isProcessRunning, previousSystemProxySnapshot != nil {
            guard restorePreviousSystemProxy() else { return false }
        }
        let wantsPrivilegedTUN = (stagedTunEnabled ?? isTunEnabled) && coreService.supportsPrivilegedTUN
        if wantsPrivilegedTUN, !coreService.isPrivilegedRunning {
            do { try coreService.authorizeTUN() }
            catch { lastErrorMessage = error.localizedDescription; return false }
        }
        if coreService.isProcessRunning,
           coreService.isPrivilegedRunning == wantsPrivilegedTUN,
           (try? await apiService.data(for: .version)) != nil {
            coreService.markRunning()
            coreStatus = coreService.status
            isCoreRunning = true
            return true
        }

        if coreService.isProcessRunning {
            guard restorePreviousSystemProxy() else { return false }
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
                routingOverrides: routingOverrides,
                privilegedTUN: wantsPrivilegedTUN
            )
            applyPreparedRuntimeConfiguration(prepared)
        } catch {
            handleCoreFailure(error.localizedDescription)
            return false
        }

        await coreService.start(
            configPath: self.configPath,
            runtimeDirectoryURL: profileRepository.runtimeDirectoryURL,
            useTUN: wantsPrivilegedTUN
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
            guard restorePreviousSystemProxy() else { return false }
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
        consecutiveControllerFailures = 0
        startRuntimeMonitorIfNeeded()
        await restoreSavedProxySelections()
        guard coreService.isProcessRunning else {
            handleCoreFailure(coreService.status.failureMessage ?? "Mihomo exited unexpectedly.")
            return false
        }
        lastErrorMessage = nil
        return true
    }

    private func validateRoutingChanges(_ overrides: [RoutingOverride]) async throws {
        guard isCoreRunning, let profile = selectedManagedProfile else { return }
        let stagingURL = profileRepository.rootURL
            .appendingPathComponent(".routing-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        let prepared = try runtimeConfigurationPreparer.prepare(
            sourceURL: profile.managedConfigURL,
            runtimeDirectoryURL: stagingURL,
            routingOverrides: overrides,
            privilegedTUN: coreService.isPrivilegedRunning
        )
        try Task.checkCancellation()
        if case let .failure(message) = await coreService.validateConfig(
            path: prepared.configURL.path, runtimeDirectoryURL: stagingURL
        ) {
            throw ManagedProfileError.validationFailed(message)
        }
        try Task.checkCancellation()
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
            guard await stopRuntime(userInitiated: true) else {
                throw RoutingRuntimeError.restartFailed(lastErrorMessage ?? "Could not restore the system proxy.")
            }
            if !(await startRuntime(configPath: configPath)) {
                throw RoutingRuntimeError.restartFailed(
                    lastErrorMessage ?? "Mihomo did not restart with the new routing rules."
                )
            }
        } else {
            guard await stopControllerOnly(userInitiated: true) else {
                throw RoutingRuntimeError.restartFailed(lastErrorMessage ?? "Could not restore the system proxy.")
            }
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

    @discardableResult
    private func stopRuntime(userInitiated: Bool) async -> Bool {
        guard restorePreviousSystemProxy() else { return false }
        runtimeGeneration += 1
        stagedOutboundMode = stagedOutboundMode ?? confirmedOutboundMode
        stagedTunEnabled = isTunEnabled
        stopTrafficStream()
        await coreService.stop(userInitiated: userInitiated)
        coreStatus = coreService.status
        isStarted = false
        isCoreRunning = false
        runtimeTickCount = 0
        latestUploadBytesPerSecond = 0
        latestDownloadBytesPerSecond = 0
        uploadSpeedText = "0B/s"
        downloadSpeedText = "0B/s"
        speedSamples = Array(repeating: 0, count: 28)
        await refreshNetworkIdentity()
        return true
    }

    @discardableResult
    private func stopControllerOnly(userInitiated: Bool) async -> Bool {
        guard restorePreviousSystemProxy() else { return false }
        runtimeGeneration += 1
        stopTrafficStream()
        await coreService.stop(userInitiated: userInitiated)
        coreStatus = coreService.status
        isStarted = false
        isCoreRunning = false
        runtimeTickCount = 0
        return true
    }

    @discardableResult
    private func restorePreviousSystemProxy() -> Bool {
        do {
            try loadSystemProxyRecoveryIfNeeded()
        } catch SystemProxyError.ownedByAnotherInstance where !coreService.isProcessRunning {
            // Closing a second, idle app must not disconnect the first app.
            return true
        } catch {
            systemProxyErrorMessage = error.localizedDescription
            return false
        }
        guard let previousSystemProxySnapshot else {
            isSystemProxyEnabled = false
            return true
        }
        lastProxyRestoreAttempt = .now
        do {
            let managed = managedSystemProxySnapshot ?? legacyManagedSystemProxySnapshot()
            try systemProxyService.restore(
                service: previousSystemProxyService ?? networkService,
                snapshot: previousSystemProxySnapshot.removingProxy(
                    host: managed.web.host, httpPort: managed.web.port, socksPort: managed.socks.port
                ),
                ownedSnapshot: managed
            )
            try systemProxyRecoveryRepository.clear()
            self.previousSystemProxySnapshot = nil
            previousSystemProxyService = nil
            managedSystemProxySnapshot = nil
            isSystemProxyEnabled = false
            systemProxyErrorMessage = nil
            return true
        } catch {
            // Some protocol settings may still point at our listener.
            isSystemProxyEnabled = true
            systemProxyErrorMessage = error.localizedDescription
            return false
        }
    }

    private func loadSystemProxyRecoveryIfNeeded() throws {
        guard let recovery = try pendingSystemProxyRecovery() else { return }
        previousSystemProxySnapshot = recovery.snapshot
        previousSystemProxyService = recovery.service
        managedSystemProxySnapshot = recovery.managedProxy
    }

    private func pendingSystemProxyRecovery() throws -> SystemProxyRecoveryState? {
        guard previousSystemProxySnapshot == nil,
              let recovery = try systemProxyRecoveryRepository.load() else { return nil }
        guard !recovery.isOwnedByRunningProcess else { throw SystemProxyError.ownedByAnotherInstance }
        return recovery
    }

    private func legacyManagedSystemProxySnapshot() -> SystemProxySnapshot {
        // Older receipts predate ownership metadata. The last runtime file
        // records the ports actually used, including automatic port changes.
        let settings = try? MihomoConfigurationInspector.inspect(url: profileRepository.runtimeConfigURL)
        return .enabled(host: proxyHost, httpPort: settings?.httpPort ?? httpPort, socksPort: settings?.socksPort ?? socksPort)
    }

    private func waitForController() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline, !Task.isCancelled {
            guard coreService.isProcessRunning else {
                coreStatus = coreService.status
                return false
            }
            if (try? await apiService.data(for: .version)) != nil {
                return true
            }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return false }
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
