import Foundation
import Testing
@testable import ClashGlassCore

@Test func primaryApplicationSectionsStayInOrder() {
    #expect(AppSection.allCases.map(\.title) == [
        "Dashboard",
        "Diagnostics",
        "Proxies",
        "Routing",
        "Profiles",
        "Connections",
        "Settings",
    ])
}

@Test func diagnosticsHasItsOwnPrimaryRailEntry() {
    #expect(AppSection.diagnostics.symbol == "stethoscope")
    #expect(RailSelectionResolver.item(for: .diagnostics) == .section(.diagnostics))
}

@Test func settingsKeepsRequiredLegalNotice() {
    #expect(ApplicationDisclaimer.purpose.contains("educational"))
    #expect(ApplicationDisclaimer.purpose.contains("research"))
    #expect(ApplicationDisclaimer.responsibility.contains("applicable laws"))
    #expect(ApplicationDisclaimer.liability.contains("provided \"as is\""))
    #expect(ApplicationDisclaimer.liability.contains("not liable"))
}

@MainActor
@Test func appStorePersistsLatencyTestSettings() throws {
    let suiteName = "ClashGlassTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: rootURL),
        userDefaults: defaults
    )
    store.latencyTestURL = " https://cp.cloudflare.com/generate_204 "
    store.latencyTestTimeoutMilliseconds = 2_500
    store.reduceMotion = true
    store.accent = .cobalt

    let restored = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: rootURL),
        userDefaults: defaults
    )
    #expect(restored.latencyTestURL == "https://cp.cloudflare.com/generate_204")
    #expect(restored.latencyTestTimeoutMilliseconds == 2_500)
    #expect(restored.reduceMotion)
    #expect(restored.accent == .cobalt)
}

@Test func decorativeAccentOptionsReserveTrafficLightColorsForStatus() {
    #expect(NexoraAccent.allCases.count == 11)
    #expect(NexoraAccent.allCases.first == .terracotta)
    let reservedNames = ["mint", "green", "red", "orange"]
    #expect(
        NexoraAccent.allCases.allSatisfy { accent in
            reservedNames.allSatisfy { !accent.rawValue.contains($0) }
        }
    )
}

@Test func appSupportsRequestedInterfaceLanguages() {
    #expect(AppLanguage.selectableCases == [
        .system,
        .english,
        .simplifiedChinese,
        .traditionalChinese,
        .japanese,
        .french,
        .russian,
        .spanish,
        .portuguese,
    ])

    for language in AppLanguage.selectableCases where language != .system {
        #expect(!language.text(.settings).isEmpty)
        #expect(!language.text(.appearance).isEmpty)
        #expect(!language.text(.language).isEmpty)
        #expect(!language.text(.about).isEmpty)
        #expect(!language.text(.update).isEmpty)
        for key in AppString.allCases {
            #expect(
                AppLocalization.hasTranslation(key, language: language),
                "Missing \(key.rawValue) in \(language.rawValue)"
            )
        }
    }

    #expect(AppLanguage.simplifiedChinese.text(.settings) == "设置")
    #expect(AppLanguage.traditionalChinese.text(.settings) == "設定")
    #expect(AppLanguage.japanese.text(.settings) == "設定")
    #expect(AppLanguage.french.text(.settings) == "Réglages")
    #expect(AppLanguage.russian.text(.settings) == "Настройки")
    #expect(AppLanguage.spanish.text(.settings) == "Ajustes")
    #expect(AppLanguage.portuguese.text(.settings) == "Definições")
}

@Test func localizedInterfaceTextCoversProxyRoutingAndAboutSurfaces() {
    let simplified = AppLanguage.simplifiedChinese
    let traditional = AppLanguage.traditionalChinese
    let japanese = AppLanguage.japanese

    #expect(simplified.text(.tab) == "标签")
    #expect(traditional.text(.list) == "列表")
    #expect(japanese.text(.selector) == "セレクター")
    #expect(simplified.localizedProxyType("Selector") == "选择器")
    #expect(traditional.localizedProxyType("Proxy") == "代理")
    #expect(simplified.profileStorageDetail(name: "Mutdot") == "配置：Mutdot · 独立保存，不修改原 YAML")
    #expect(traditional.ruleCount(1) == "1 條規則")
    #expect(traditional.ruleCount(2) == "2 條規則")
    #expect(simplified.text(.routingExplanation).contains("直连规则"))
    #expect(traditional.text(.poweredByMihomo) == "由 Mihomo 驅動")
}

@Test func profileHealthFilterMatchesValidationStates() {
    let valid = ProfileValidationState.valid()
    let invalid = ProfileValidationState.invalid("bad config")

    #expect(ProfileHealthFilter.all.matches(.notValidated))
    #expect(ProfileHealthFilter.all.matches(.checking))
    #expect(ProfileHealthFilter.all.matches(valid))
    #expect(ProfileHealthFilter.all.matches(invalid))

    #expect(ProfileHealthFilter.needsFix.matches(invalid))
    #expect(!ProfileHealthFilter.needsFix.matches(valid))
    #expect(ProfileHealthFilter.notChecked.matches(.notValidated))
    #expect(ProfileHealthFilter.notChecked.matches(.checking))
    #expect(!ProfileHealthFilter.notChecked.matches(valid))
    #expect(ProfileHealthFilter.valid.matches(valid))
    #expect(!ProfileHealthFilter.valid.matches(invalid))
}

@Test func proxyNodeFilterFindsSelectedUntestedAndSlowNodes() {
    let selected = ProxyNode(name: "Japan", region: "JP", latency: 80, isSelected: true)
    let untested = ProxyNode(name: "Singapore", region: "SG", latency: nil, isSelected: false)
    let slow = ProxyNode(name: "US", region: "US", latency: 480, isSelected: false)
    let group = ProxyNode(name: "Auto", region: "Proxy", latency: nil, isSelected: false, isGroup: true)

    #expect(ProxyNodeFilter.all.matches(selected))
    #expect(ProxyNodeFilter.selected.matches(selected))
    #expect(!ProxyNodeFilter.selected.matches(untested))
    #expect(ProxyNodeFilter.untested.matches(untested))
    #expect(!ProxyNodeFilter.untested.matches(group))
    #expect(ProxyNodeFilter.slow.matches(slow))
    #expect(!ProxyNodeFilter.slow.matches(selected))
}

@Test func networkDiagnosticReportExplainsSystemTunnelEgress() {
    let report = NetworkDiagnosticEngine.report(
        snapshot: NetworkDiagnosticSnapshot(
            isStarted: false,
            isSystemProxyEnabled: true,
            isTunEnabled: false,
            activeSystemTunnel: true,
            egressKind: .systemTunnel,
            externalIP: "151.242.36.41",
            countryCode: "JP",
            countryName: "Japan",
            intranetIP: "192.168.1.65",
            httpPort: 7890,
            socksPort: 7891,
            selectedMode: .rule,
            selectedProfile: "Mutdot"
        )
    )

    #expect(report.severity == .warning)
    #expect(report.summary.contains("System tunnel"))
    #expect(report.findings.contains { $0.title.contains("utun") })
    #expect(report.suggestedAction == "Turn off the other VPN/TUN, then refresh.")
    #expect(report.copyText.contains("151.242.36.41"))
    #expect(report.copyText.contains("System tunnel"))
}

@Test func networkDiagnosticReportNamesSystemTunnelWhenStartedRuntimeFallsBackToTunnel() {
    let report = NetworkDiagnosticEngine.report(
        snapshot: NetworkDiagnosticSnapshot(
            isStarted: true,
            isSystemProxyEnabled: true,
            isTunEnabled: true,
            activeSystemTunnel: true,
            egressKind: .systemTunnel,
            externalIP: "151.242.36.41",
            countryCode: "JP",
            countryName: "Japan",
            intranetIP: "192.168.1.65",
            httpPort: 7890,
            socksPort: 7891,
            selectedMode: .rule,
            selectedProfile: "Mutdot"
        )
    )

    #expect(report.severity == .warning)
    #expect(report.summary.contains("System tunnel"))
    #expect(report.suggestedAction == "Turn off the other VPN/TUN, then refresh.")
    #expect(!report.summary.localizedCaseInsensitiveContains("direct egress"))
    #expect(!report.copyText.localizedCaseInsensitiveContains("direct egress"))
}

@Test func networkDiagnosticReportHighlightsDNSAndEndpointFailures() {
    let report = NetworkDiagnosticEngine.report(
        snapshot: NetworkDiagnosticSnapshot(
            isStarted: true,
            isSystemProxyEnabled: true,
            isTunEnabled: true,
            activeSystemTunnel: false,
            egressKind: .proxy,
            externalIP: "203.0.113.10",
            countryCode: "US",
            countryName: "United States",
            intranetIP: "192.168.1.65",
            httpPort: 7890,
            socksPort: 7891,
            selectedMode: .rule,
            selectedProfile: "Mutdot",
            dnsChecks: [
                NetworkDNSCheck(
                    host: "api4.ipify.org",
                    addresses: [],
                    errorMessage: "nodename nor servname provided"
                ),
            ],
            endpointChecks: [
                NetworkEndpointCheck(
                    name: "ipwho.is",
                    url: URL(string: "https://ipwho.is/")!,
                    isReachable: false,
                    statusCode: nil,
                    latencyMilliseconds: nil,
                    errorMessage: "timed out"
                ),
            ]
        )
    )

    #expect(report.severity == .critical)
    #expect(report.findings.contains { $0.title == "DNS resolution" })
    #expect(report.findings.contains { $0.title == "External probes" })
    #expect(report.copyText.contains("api4.ipify.org"))
    #expect(report.copyText.contains("ipwho.is"))
}

@Test func networkDiagnosticCopiedReportIncludesProbeEvidenceSections() {
    let report = NetworkDiagnosticEngine.report(
        snapshot: NetworkDiagnosticSnapshot(
            isStarted: true,
            isSystemProxyEnabled: true,
            isTunEnabled: false,
            activeSystemTunnel: false,
            egressKind: .proxy,
            externalIP: "203.0.113.10",
            countryCode: "US",
            countryName: "United States",
            intranetIP: "192.168.1.65",
            httpPort: 7890,
            socksPort: 7891,
            selectedMode: .rule,
            selectedProfile: "Mutdot",
            portChecks: [
                NetworkPortCheck(
                    label: "HTTP Proxy",
                    port: 7890,
                    isListening: true,
                    ownerName: "ClashGlass",
                    ownerPID: 42
                ),
                NetworkPortCheck(label: "Socks Proxy", port: 7891, isListening: false),
            ],
            dnsChecks: [
                NetworkDNSCheck(host: "github.com", addresses: ["140.82.112.4"]),
                NetworkDNSCheck(host: "api4.ipify.org", addresses: [], errorMessage: "lookup failed"),
            ],
            endpointChecks: [
                NetworkEndpointCheck(
                    name: "ipwho.is",
                    url: URL(string: "https://ipwho.is/")!,
                    isReachable: true,
                    statusCode: 200,
                    latencyMilliseconds: 124,
                    errorMessage: nil
                ),
                NetworkEndpointCheck(
                    name: "api4.ipify",
                    url: URL(string: "https://api4.ipify.org?format=json")!,
                    isReachable: false,
                    statusCode: nil,
                    latencyMilliseconds: nil,
                    errorMessage: "timed out"
                ),
            ]
        )
    )

    #expect(report.copyText.contains("Route: profile=Mutdot, mode=Rule, egress=proxy"))
    #expect(report.copyText.contains("Ports:"))
    #expect(report.copyText.contains("- HTTP Proxy :7890 listening ClashGlass pid 42"))
    #expect(report.copyText.contains("- Socks Proxy :7891 not listening"))
    #expect(report.copyText.contains("DNS:"))
    #expect(report.copyText.contains("- github.com 140.82.112.4"))
    #expect(report.copyText.contains("- api4.ipify.org failed lookup failed"))
    #expect(report.copyText.contains("Endpoints:"))
    #expect(report.copyText.contains("- ipwho.is HTTP 200 124 ms"))
    #expect(report.copyText.contains("- api4.ipify failed timed out"))
}

@Test func networkDiagnosticBriefHighlightsTheFirstBlockingLayer() {
    let report = NetworkDiagnosticEngine.report(
        snapshot: NetworkDiagnosticSnapshot(
            isStarted: true,
            isSystemProxyEnabled: true,
            isTunEnabled: true,
            activeSystemTunnel: false,
            egressKind: .proxy,
            externalIP: "203.0.113.10",
            countryCode: "US",
            countryName: "United States",
            intranetIP: "192.168.1.65",
            httpPort: 7890,
            socksPort: 7891,
            selectedMode: .rule,
            selectedProfile: "Mutdot",
            dnsChecks: [
                NetworkDNSCheck(
                    host: "api4.ipify.org",
                    addresses: [],
                    errorMessage: "nodename nor servname provided"
                ),
            ]
        )
    )

    let brief = NetworkDiagnosticBrief.make(
        report: report,
        totalChecks: 8,
        egressTitle: "Proxy Egress",
        profileTitle: "Mutdot"
    )

    #expect(brief.headline == "Blocking layer detected")
    #expect(brief.detail.contains("DNS resolution"))
    #expect(brief.detail.contains("8 checks"))
    #expect(brief.metrics.map(\.value) == ["8", "Proxy Egress", "Mutdot"])
}

@Test func networkDiagnosticBriefLocalizesToolbarAndProtectsLongExitNames() {
    let brief = NetworkDiagnosticBrief.make(
        report: .placeholder,
        totalChecks: 0,
        egressTitle: AppLanguage.russian.text(.systemTunnelEgress),
        profileTitle: "Mutdot",
        language: .russian
    )

    #expect(brief.headline == "Готово к диагностике")
    #expect(brief.detail == "Диагностика сети · 0")
    #expect(brief.metrics.map(\.title) == ["Проверки", "Выход", "Профиль"])
    #expect(
        DiagnosticsToolbarLayoutMetrics.exitWidth
            > DiagnosticsToolbarLayoutMetrics.checksWidth
    )
    #expect(
        DiagnosticsToolbarLayoutMetrics.width(for: "globe")
            == DiagnosticsToolbarLayoutMetrics.exitWidth
    )
}

@Test func networkDiagnosticReportDoesNotClaimProxyEgressAfterDirectFallback() {
    let report = NetworkDiagnosticEngine.report(
        snapshot: NetworkDiagnosticSnapshot(
            isStarted: true,
            isSystemProxyEnabled: true,
            isTunEnabled: false,
            activeSystemTunnel: false,
            egressKind: .direct,
            externalIP: "203.0.113.8",
            countryCode: "US",
            countryName: "United States",
            intranetIP: "192.168.1.65",
            httpPort: 7890,
            socksPort: 7891,
            selectedMode: .rule,
            selectedProfile: "Mutdot"
        )
    )

    #expect(report.summary.contains("direct"))
    #expect(!report.summary.contains("proxy egress is active"))
    #expect(!report.copyText.contains("showing the proxy egress"))
}

@Test func systemAppearanceResolvesFromTheLiveMacOSScheme() {
    #expect(AppAppearance.system.resolvedColorScheme(systemColorScheme: .light) == .light)
    #expect(AppAppearance.system.resolvedColorScheme(systemColorScheme: .dark) == .dark)
    #expect(AppAppearance.light.resolvedColorScheme(systemColorScheme: .dark) == .light)
    #expect(AppAppearance.dark.resolvedColorScheme(systemColorScheme: .light) == .dark)
}

@Test func updateCapsuleDefersToSparkleForDownloadedOrVisibleUpdates() {
    #expect(UpdateReminderPolicy.shouldShowCapsule(
        standardDriverWillShowUpdate: false,
        updateIsNotDownloaded: true
    ))
    #expect(!UpdateReminderPolicy.shouldShowCapsule(
        standardDriverWillShowUpdate: true,
        updateIsNotDownloaded: true
    ))
    #expect(!UpdateReminderPolicy.shouldShowCapsule(
        standardDriverWillShowUpdate: false,
        updateIsNotDownloaded: false
    ))
}

@MainActor
@Test func appStorePersistsTheSelectedLanguage() throws {
    let suiteName = "ClashGlassTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: rootURL),
        userDefaults: defaults
    )
    store.language = .japanese

    let restored = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: rootURL),
        userDefaults: defaults
    )
    #expect(restored.language == .japanese)
}

@MainActor
@Test func appStoreStartsWithoutPrototypeSampleData() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let repository = ManagedProfileRepository(rootURL: rootURL)
    let store = AppStore(profileRepository: repository)

    #expect(store.selectedProfile == "No Profile")
    #expect(store.proxyGroups.isEmpty)
    #expect(store.connections.isEmpty)
}

@Test func settingsReplacesToolsInThePrimaryRail() {
    #expect(AppSection.settings.symbol == "wrench.and.screwdriver.fill")
    #expect(RailSelectionResolver.item(for: .settings) == .section(.settings))
}

@Test func coreStatusPresentationDistinguishesControllerOnlyFromStopped() {
    #expect(CoreStatusPresentation.runtimeText(isStarted: true, isCoreRunning: true) == "VPN Active")
    #expect(CoreStatusPresentation.runtimeText(isStarted: false, isCoreRunning: true) == "Controller Running")
    #expect(CoreStatusPresentation.runtimeText(isStarted: false, isCoreRunning: false) == "Stopped")
}

@Test func toolbarControlsMatchTheReferencePaletteAndAlignment() {
    #expect(ToolbarControlAppearancePolicy.runningCoreSymbol == "checkmark")
    #expect(ToolbarControlAppearancePolicy.stoppedCoreSymbol == "arrow.clockwise")
    #expect(!ToolbarControlAppearancePolicy.runningCoreUsesSolidGreenSurface)
    #expect(!ToolbarControlAppearancePolicy.runningCoreUsesWhiteSymbol)
    #expect(ToolbarControlAppearancePolicy.quickEditUsesNativeMenu)
    #expect(!ToolbarControlAppearancePolicy.quickEditUsesPlainIcon)
    #expect(ToolbarControlAppearancePolicy.quickEditUsesCompactGlassSurface)
    #expect(ToolbarControlAppearancePolicy.quickEditKeepsSurfaceOutsideNativeMenuLabel)
    #expect(!ToolbarControlAppearancePolicy.quickEditVisualSurfaceAllowsHitTesting)
    #expect(!ToolbarControlAppearancePolicy.quickEditHitLayerUsesVisibleAlpha)
    #expect(ToolbarControlAppearancePolicy.quickEditUsesSingleInteractiveSurface)
    #expect(ToolbarControlAppearancePolicy.quickEditUsesAppKitMenuBridge)
    #expect(ToolbarControlAppearancePolicy.quickEditSymbol == "pencil")
    #expect(ToolbarControlMetrics.visibleSize == 34)
    #expect(ToolbarControlMetrics.hitTarget == 40)
    #expect(ToolbarControlAppearancePolicy.controlCornerRadius == 11)
    #expect(MainStageLayoutMetrics.toolbarHeight == ToolbarControlMetrics.hitTarget)
    #expect(MainStageLayoutMetrics.toolbarToContentSpacing == 24)
    #expect(MainStageLayoutMetrics.contentHeightDeduction == 64)
    #expect(!MainStageLayoutMetrics.runtimeControlOverlaysContent)
    #expect(MainStageLayoutMetrics.contentHeight(stageHeight: 720) == 656)
}

@Test func pageNavigationKeepsHeavyFeatureContentStable() {
    #expect(PageNavigationTransitionPolicy.animatesTitleChange)
    #expect(!PageNavigationTransitionPolicy.crossfadesFeatureContent)
    #expect(PageNavigationTransitionPolicy.respectsReducedMotion)
    #expect(PageNavigationTransitionPolicy.duration == 0.16)
}

@Test func appMotionPolicyCombinesSystemAndAppPreferences() {
    #expect(!AppMotionPolicy.reducesMotion(systemPreference: false, appPreference: false))
    #expect(AppMotionPolicy.reducesMotion(systemPreference: true, appPreference: false))
    #expect(AppMotionPolicy.reducesMotion(systemPreference: false, appPreference: true))
    #expect(AppMotionPolicy.reducesMotion(systemPreference: true, appPreference: true))
}

@Test func liquidControlMotionUsesStableHoverAndPressScales() {
    #expect(LiquidControlMotion.scale(isHovering: false, isPressed: false, reduceMotion: false) == 1)
    #expect(LiquidControlMotion.scale(isHovering: true, isPressed: false, reduceMotion: false) == 1.025)
    #expect(LiquidControlMotion.scale(isHovering: true, isPressed: true, reduceMotion: false) == 0.975)
    #expect(LiquidControlMotion.scale(isHovering: true, isPressed: true, reduceMotion: true) == 1)
    #expect(LiquidControlInteractionPolicy.usesNativeButtonPressState)
    #expect(!LiquidControlInteractionPolicy.usesSupplementalDragGesture)
    #expect(!LiquidControlInteractionPolicy.nestsInteractiveGlassInsideButton)
    #expect(LiquidControlInteractionPolicy.usesNativeButtonAction)
    #expect(!LiquidControlInteractionPolicy.triggersActionOnPressDown)
    #expect(LiquidControlInteractionPolicy.minimumHitTarget >= 40)
    #expect(ToolbarControlMetrics.visibleSize == 34)
    #expect(ToolbarControlMetrics.hitTarget > ToolbarControlMetrics.visibleSize)
}

@Test func railUsesAFullWidthPointerTarget() {
    #expect(RailHitTargetMetrics.width == 74)
    #expect(RailHitTargetMetrics.height >= 44)
}

@Test func glassCardMotionProvidesIndependentHoverLift() {
    #expect(GlassCardMotion.scale(isHovering: false, reduceMotion: false) == 1)
    #expect(GlassCardMotion.scale(isHovering: true, reduceMotion: false) == 1.004)
    #expect(GlassCardMotion.verticalOffset(isHovering: true, reduceMotion: false) == -1)
    #expect(GlassCardMotion.shadowOpacity(isHovering: false, reduceMotion: false) == 0)
    #expect(GlassCardMotion.shadowOpacity(isHovering: true, reduceMotion: false) == 0.12)
    #expect(GlassCardMotion.shadowOpacity(isHovering: true, reduceMotion: true) == 0.08)
    #expect(GlassCardMotion.scale(isHovering: true, reduceMotion: true) == 1)
    #expect(GlassCardMotion.verticalOffset(isHovering: true, reduceMotion: true) == 0)
}

@Test func glassCardReservesEnoughOverflowForAnUnclippedHoverHalo() {
    #expect(GlassCardVisualMetrics.usesStableGlassMaterial)
    #expect(GlassCardVisualMetrics.clipsContentToRoundedShape)
    #expect(GlassCardVisualMetrics.overflowAllowance >= GlassCardVisualMetrics.shadowRadius)
    #expect(
        GlassCardVisualMetrics.overflowAllowance
            >= GlassCardVisualMetrics.shadowRadius + abs(GlassCardVisualMetrics.shadowVerticalOffset)
    )
    #expect(PageSurfaceMetrics.horizontalInset >= GlassCardVisualMetrics.minimumPageInset)
    #expect(PageSurfaceMetrics.topInset >= GlassCardVisualMetrics.minimumPageInset)
}

@Test func featurePagesKeepContentAwayFromEveryStageEdge() {
    #expect(PageSurfaceMetrics.horizontalInset == 28)
    #expect(PageSurfaceMetrics.topInset == 28)
    #expect(PageSurfaceMetrics.contentWidth(availableWidth: 854) == 798)
}

@Test func railHoverTracksOnlyThePointerTarget() {
    var hoverState = RailHoverState()
    let dashboard = RailItem.section(.dashboard)
    let profiles = RailItem.section(.profiles)

    hoverState.update(item: dashboard, isHovering: true)
    #expect(hoverState.hoveredItem == dashboard)

    hoverState.update(item: profiles, isHovering: true)
    #expect(hoverState.hoveredItem == profiles)

    hoverState.update(item: dashboard, isHovering: false)
    #expect(hoverState.hoveredItem == profiles)

    hoverState.update(item: profiles, isHovering: false)
    #expect(hoverState.hoveredItem == nil)
}

@Test func railItemsStayPlainUntilSelectedOrHovered() {
    let dashboard = RailItem.section(.dashboard)
    let profiles = RailItem.section(.profiles)
    let selected = RailItemPresentation(
        item: dashboard,
        selectedSection: .dashboard,
        hoveredItem: nil,
        reduceMotion: false
    )
    let idle = RailItemPresentation(
        item: profiles,
        selectedSection: .dashboard,
        hoveredItem: nil,
        reduceMotion: false
    )
    let hovered = RailItemPresentation(
        item: profiles,
        selectedSection: .dashboard,
        hoveredItem: profiles,
        reduceMotion: false
    )

    #expect(selected.showsSelectionBackground)
    #expect(selected.scale == 1)
    #expect(!idle.showsSelectionBackground)
    #expect(idle.scale == 1)
    #expect(!hovered.showsSelectionBackground)
    #expect(hovered.scale == 1)
}

@Test func railItemsUseQuietHoverWithoutLayoutMotion() {
    let dashboard = RailItem.section(.dashboard)
    let profiles = RailItem.section(.profiles)
    let selected = RailItemPresentation(
        item: dashboard,
        selectedSection: .dashboard,
        hoveredItem: nil,
        reduceMotion: false
    )
    let hovered = RailItemPresentation(
        item: profiles,
        selectedSection: .dashboard,
        hoveredItem: profiles,
        reduceMotion: false
    )
    let reducedHover = RailItemPresentation(
        item: profiles,
        selectedSection: .dashboard,
        hoveredItem: profiles,
        reduceMotion: true
    )

    #expect(selected.iconScale == 1)
    #expect(selected.horizontalOffset == 0)
    #expect(!selected.showsHoverBackground)
    #expect(hovered.showsHoverBackground)
    #expect(hovered.scale == 1)
    #expect(hovered.iconScale == 1.035)
    #expect(hovered.horizontalOffset == 0)
    #expect(hovered.verticalOffset == 0)
    #expect(hovered.shadowOpacity == 0)
    #expect(hovered.selectionGlowOpacity == 0.08)
    #expect(reducedHover.scale == 1)
    #expect(reducedHover.iconScale == 1)
    #expect(reducedHover.horizontalOffset == 0)
    #expect(reducedHover.showsHoverBackground)
}

@Test func railSelectionFollowsEveryNavigationEntryPoint() {
    #expect(RailSelectionMotion.appliesToExternalSectionChanges)
    #expect(RailSelectionMotion.usesMatchedGeometry)
    #expect(RailSelectionMotion.respectsReducedMotion)

    #expect(RailSelectionResolver.item(for: .dashboard) == .section(.dashboard))
    #expect(RailSelectionResolver.item(for: .proxies) == .section(.proxies))
    #expect(RailSelectionResolver.item(for: .routing) == .section(.routing))
    #expect(RailSelectionResolver.item(for: .profiles) == .section(.profiles))
    #expect(RailSelectionResolver.item(for: .settings) == .section(.settings))
}

@Test func railUsesTheWindowBackgroundAndDrawsAboveTheMainStage() {
    #expect(RailSurfaceMetrics.usesSystemGlassSelection == false)
    #expect(RailSurfaceMetrics.backgroundMatchesWindow)
    #expect(RailSurfaceMetrics.railZIndex > RailSurfaceMetrics.stageZIndex)
    #expect(
        RailSurfaceMetrics.selectionShadowRadius
            <= RailSurfaceMetrics.selectionTrailingClearance
    )
}

@Test func selectionIndicatorMovesWithoutMovingItsLabel() {
    #expect(SelectionControlMotion.indicatorScale(
        isHovering: false,
        isPressed: false,
        reduceMotion: false
    ) == 1)
    #expect(SelectionControlMotion.indicatorScale(
        isHovering: true,
        isPressed: false,
        reduceMotion: false
    ) == 1.08)
    #expect(SelectionControlMotion.indicatorScale(
        isHovering: true,
        isPressed: true,
        reduceMotion: false
    ) == 0.92)
    #expect(SelectionControlMotion.indicatorScale(
        isHovering: true,
        isPressed: true,
        reduceMotion: true
    ) == 1)
    #expect(SelectionControlMotion.labelScale == 1)
    #expect(ModeRowInteractionPolicy.usesFullRowHitTarget)
    #expect(ModeRowInteractionPolicy.animatesIndicatorOnly)
    #expect(ModeRowInteractionPolicy.usesNativeButtonAction)
    #expect(!ModeRowInteractionPolicy.triggersActionOnPressDown)
    #expect(ModeRowInteractionPolicy.minimumHitHeight >= 40)
}
