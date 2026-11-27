import Foundation

public enum AppString: String, CaseIterable, Sendable {
    case settings
    case settingsSubtitle
    case appearance
    case colorScheme
    case accentColor
    case reduceMotion
    case glassAppearance
    case blurStrength
    case glassBlurHint
    case glassAccessibilityHint
    case resetGlassAppearance
    case system
    case light
    case dark
    case language
    case systemDefault
    case latencyTesting
    case latencyTestURL
    case latencyTestTimeout
    case about
    case version
    case engine
    case legalNotice
    case permittedUse
    case yourResponsibility
    case noWarranty
    case thirdPartyServices
    case indemnification
    case disclaimerPurpose
    case disclaimerResponsibility
    case disclaimerLiability
    case disclaimerThirdParties
    case disclaimerIndemnity
    case update
    case checkForUpdates
    case checkingForUpdates
    case updateAvailableTitle
    case updateAvailableMessage
    case updateWithSparkle
    case updateLater
    case upToDateTitle
    case upToDateMessage
    case updateCheckFailedTitle
    case updateCheckFailedMessage
    case updateCheckUnavailable
    case dashboard
    case diagnostics
    case proxies
    case routing
    case profiles
    case connections
    case coreStatus
    case quickEdit
    case cancel
    case confirm
    case restartCore
    case startCore
    case renameProfile
    case profileName
    case rename
    case systemProxy
    case networkSpeed
    case networkDetection
    case networkDoctor
    case websiteComparisonTitle
    case websiteComparisonHint
    case websiteURL
    case websiteURLPlaceholder
    case websiteCompare
    case websiteDirectRoute
    case websiteNexoraRoute
    case websiteDirectHint
    case websiteNexoraHint
    case websiteTunnelWarning
    case websiteInvalidURL
    case websiteProxyInactive
    case websiteResponseReceived
    case websiteHTTPRestricted
    case websiteDNSFailure
    case websiteConnectionFailure
    case websiteTLSFailure
    case websiteTimeout
    case websiteRequestFailure
    case websiteProxyAuthentication
    case websiteCancelled
    case websiteStaleHint
    case websiteDNSTime
    case websiteTotalTime
    case websiteWaiting
    case websiteCopyResults
    case runNetworkDoctor
    case diagnosticSnapshot
    case diagnosticExplanationTitle
    case diagnosticExplanationPlaceholder
    case diagnosticExplanationRules
    case diagnosticExplanationModel
    case diagnosticExplanationEvidence
    case diagnosticExplanationNextSteps
    case diagnosticExplanationAIAction
    case diagnosticExplanationGenerating
    case diagnosticExplanationSnapshotHint
    case diagnosticExplanationPrivacyHint
    case diagnosticExplanationUnsupportedSystem
    case diagnosticExplanationIntelligenceDisabled
    case diagnosticExplanationModelNotReady
    case diagnosticExplanationDeviceIneligible
    case diagnosticExplanationModelUnavailable
    case diagnosticExplanationFallback
    case diagnosticExplanationStale
    case diagnosticExplanationStaleHint
    case networkDiagnosisHint
    case diagnosticReadyHeadline
    case diagnosticBlockingHeadline
    case diagnosticAttentionHeadline
    case diagnosticCleanHeadline
    case diagnosticReadyDetailFormat
    case diagnosticResultDetailFormat
    case diagnosticChecks
    case diagnosticExit
    case portRadar
    case findings
    case dnsProbe
    case endpointProbe
    case diagnose
    case copyReport
    case suggestedAction
    case detectingEgress
    case directEgress
    case proxyEgress
    case systemTunnelEgress
    case unavailableEgress
    case outboundMode
    case trafficUsage
    case intranetIP
    case options
    case rule
    case global
    case direct
    case upload
    case download
    case search
    case clearSearch
    case closeAll
    case refresh
    case noConnections
    case host
    case chain
    case closeConnection
    case ready
    case errors
    case warnings
    case stopped
    case connected
    case coreRunning
    case nodes
    case allNodes
    case selectedOnly
    case untested
    case slowNodes
    case noProxyNodes
    case noMatchingNodes
    case menuSelectedNode
    case menuNodes
    case menuQuickAccess
    case updating
    case validateAll
    case openManagedFolder
    case importYAML
    case importConfiguration
    case importFromFile
    case importFileHint
    case importFromURL
    case importURLHint
    case profileURL
    case downloadAndImport
    case importingProfile
    case invalidProfileURL
    case profileDownloadHTTPErrorFormat
    case profileDownloadInvalidResponse
    case profileDownloadEmpty
    case profileDownloadNotConfiguration
    case noMatchingProfiles
    case allProfiles
    case deleteProfile
    case managedYAML
    case running
    case current
    case managed
    case selected
    case profileTrafficLeftGBFormat
    case profileTrafficLeftPercentFormat
    case profileTrafficUnavailable
    case profileTrafficUpdatedFormat
    case profileTrafficSnapshot
    case profileTrafficSnapshotHelpFormat
    case profileTrafficLocal
    case profileTrafficLocalHelp
    case profileTrafficNotReported
    case profileTrafficNotReportedHelp
    case profileTrafficRefreshFailed
    case use
    case validate
    case notValidated
    case checking
    case valid
    case invalid
    case revealInFinder
    case delete
    case delayTest
    case automatic
    case collapse
    case expand
    case addRule
    case saving
    case domainRouting
    case deleteRule
    case noMatchingRoutingRules
    case addDomainHint
    case start
    case pause
    case tab
    case list
    case selector
    case proxy
    case urlTest
    case fallback
    case loadBalance
    case profileStorageFormat
    case selectProfileBeforeRules
    case ruleCountSingular
    case ruleCountPlural
    case routingExplanation
    case poweredByMihomo
    case ok
    case renameMenuBarNote
    case restartActiveExplanation
    case restartControllerExplanation
    case startControllerExplanation
    case deleteProfileFormat
    case profile
    case deleteProfileExplanation
}

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case french = "fr"
    case russian = "ru"
    case spanish = "es"
    case portuguese = "pt"

    public var id: Self { self }

    public static let selectableCases: [Self] = [
        .system,
        .english,
        .simplifiedChinese,
        .traditionalChinese,
        .japanese,
        .french,
        .russian,
        .spanish,
        .portuguese,
    ]

    public var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    public var nativeDisplayName: String {
        switch self {
        case .system: text(.systemDefault)
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .french: "Français"
        case .russian: "Русский"
        case .spanish: "Español"
        case .portuguese: "Português"
        }
    }

    public func text(_ key: AppString) -> String {
        AppLocalization.text(key, language: resolvedLanguage)
    }

    public func localizedProxyType(_ rawValue: String) -> String {
        let normalized = rawValue
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return switch normalized {
        case "selector": text(.selector)
        case "proxy": text(.proxy)
        case "urltest": text(.urlTest)
        case "fallback": text(.fallback)
        case "loadbalance": text(.loadBalance)
        default: rawValue
        }
    }

    public func profileStorageDetail(name: String) -> String {
        String(format: text(.profileStorageFormat), locale: locale, name)
    }

    public func ruleCount(_ count: Int) -> String {
        let key: AppString = count == 1 ? .ruleCountSingular : .ruleCountPlural
        return String(format: text(key), locale: locale, count)
    }

    public func deleteProfilePrompt(name: String?) -> String {
        String(
            format: text(.deleteProfileFormat),
            locale: locale,
            name ?? text(.profile)
        )
    }

    public func updateAvailableMessage(currentVersion: String, latestVersion: String) -> String {
        String(
            format: text(.updateAvailableMessage),
            locale: locale,
            currentVersion,
            latestVersion
        )
    }

    public func upToDateMessage(currentVersion: String) -> String {
        String(
            format: text(.upToDateMessage),
            locale: locale,
            currentVersion
        )
    }

    public func updateCheckFailedMessage(detail: String) -> String {
        String(
            format: text(.updateCheckFailedMessage),
            locale: locale,
            detail
        )
    }

    private var resolvedLanguage: Self {
        guard self == .system else {
            return self
        }
        let identifier = Locale.autoupdatingCurrent.identifier.lowercased()
        if identifier.hasPrefix("zh") {
            return identifier.contains("hant")
                || identifier.contains("_tw")
                || identifier.contains("_hk")
                || identifier.contains("_mo")
                ? .traditionalChinese
                : .simplifiedChinese
        }
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("fr") { return .french }
        if identifier.hasPrefix("ru") { return .russian }
        if identifier.hasPrefix("es") { return .spanish }
        if identifier.hasPrefix("pt") { return .portuguese }
        return .english
    }
}

enum AppLocalization {
    static func text(_ key: AppString, language: AppLanguage) -> String {
        translations[language]?[key] ?? translations[.english]![key]!
    }

    static func hasTranslation(_ key: AppString, language: AppLanguage) -> Bool {
        translations[language]?[key] != nil
    }

    private static let translations: [AppLanguage: [AppString: String]] = [
        .english: [
            .clearSearch: "Clear search",
            .websiteComparisonTitle: "Website connection comparison",
            .websiteComparisonHint: "Enter a problem URL to compare direct access with the current Nexora route.",
            .websiteURL: "Website URL",
            .websiteURLPlaceholder: "example.com or https://example.com/path",
            .websiteCompare: "Compare website",
            .websiteDirectRoute: "Direct",
            .websiteNexoraRoute: "Via Nexora",
            .websiteDirectHint: "Bypasses system proxy settings.",
            .websiteNexoraHint: "Follows the current mode and rules; this route may also be direct.",
            .websiteTunnelWarning: "A system tunnel is active: both requests may use it. Direct does not represent switching the VPN off.",
            .websiteInvalidURL: "Enter a valid HTTP(S) URL without an embedded username or password.",
            .websiteProxyInactive: "No running Nexora proxy is available.",
            .websiteResponseReceived: "Server responded.",
            .websiteHTTPRestricted: "Server responded; check sign-in, access permissions or website status.",
            .websiteDNSFailure: "DNS lookup failed.",
            .websiteConnectionFailure: "Could not establish a connection.",
            .websiteTLSFailure: "HTTPS certificate or secure handshake failed.",
            .websiteTimeout: "Request timed out.",
            .websiteRequestFailure: "Request did not complete. Try again.",
            .websiteProxyAuthentication: "The proxy requires authentication.",
            .websiteCancelled: "Cancelled. You can run the comparison again.",
            .websiteStaleHint: "Network settings or URL changed. Run the comparison again.",
            .websiteDNSTime: "DNS",
            .websiteTotalTime: "Total",
            .websiteWaiting: "Waiting for a test",
            .websiteCopyResults: "Copy comparison results",
            .profileDownloadNotConfiguration: "The server did not return a Clash/Mihomo YAML configuration. Copy the Clash/Mihomo subscription link from your provider.",
            .profileTrafficSnapshot: "YAML snapshot",
            .profileTrafficSnapshotHelpFormat: "YAML snapshot from %@. Import a subscription URL for live quota updates.",
            .profileTrafficLocal: "Local YAML",
            .profileTrafficLocalHelp: "This local YAML does not include quota information. Import the subscription URL to retrieve provider usage.",
            .profileTrafficNotReported: "No provider quota",
            .profileTrafficNotReportedHelp: "The subscription server did not provide quota information.",
            .profileTrafficRefreshFailed: "Refresh failed; showing the last saved usage.",
            .profileTrafficLeftGBFormat: "%@ GB left",
            .profileTrafficLeftPercentFormat: "%@ left",
            .profileTrafficUnavailable: "Traffic unavailable",
            .profileTrafficUpdatedFormat: "Provider usage updated %@",
            .importFromFile: "Import from File",
            .importFileHint: "Choose or drag in a YAML file",
            .importFromURL: "Import from URL",
            .importURLHint: "Paste a link to a Mihomo YAML configuration.",
            .profileURL: "Profile URL",
            .downloadAndImport: "Download & Import",
            .importingProfile: "Importing…",
            .invalidProfileURL: "Enter a valid http:// or https:// URL.",
            .profileDownloadHTTPErrorFormat: "Download failed (HTTP %d).",
            .profileDownloadInvalidResponse: "The server did not return a valid HTTP response.",
            .profileDownloadEmpty: "The downloaded configuration is empty.",
            .glassAppearance: "Glass & Blur",
            .blurStrength: "Blur strength",
            .glassBlurHint: "Higher values create a more frosted background and cards. Text and controls stay sharp.",
            .glassAccessibilityHint: "Reduce Transparency in macOS takes priority over these settings.",
            .resetGlassAppearance: "Reset",

            .menuQuickAccess: "Quick Access",
            .menuNodes: "Nodes",
            .noMatchingNodes: "No matching nodes",
            .menuSelectedNode: "Selected node",
            .updating: "Updating…",
            .settings: "Settings",
            .settingsSubtitle: "Personalize Nexora and review application information.",
            .appearance: "Appearance",
            .colorScheme: "Color Scheme",
            .accentColor: "Accent Color",
            .reduceMotion: "Reduce Motion",
            .system: "System",
            .light: "Light",
            .dark: "Dark",
            .language: "Language",
            .systemDefault: "System Default",
            .latencyTesting: "Latency Testing",
            .latencyTestURL: "Test URL",
            .latencyTestTimeout: "Timeout",
            .about: "About",
            .version: "Version",
            .engine: "Engine",
            .legalNotice: "Legal Notice",
            .permittedUse: "Permitted Use",
            .yourResponsibility: "Your Responsibility",
            .noWarranty: "No Warranty and Limitation of Liability",
            .thirdPartyServices: "Third-Party Services",
            .indemnification: "Indemnification",
            .disclaimerPurpose: ApplicationDisclaimer.purpose,
            .disclaimerResponsibility: ApplicationDisclaimer.responsibility,
            .disclaimerLiability: ApplicationDisclaimer.liability,
            .disclaimerThirdParties: ApplicationDisclaimer.thirdParties,
            .disclaimerIndemnity: ApplicationDisclaimer.indemnity,
            .update: "Update",
            .checkForUpdates: "Check for Updates",
            .checkingForUpdates: "Checking for Updates…",
            .updateAvailableTitle: "Update Available",
            .updateAvailableMessage: "A newer version of Nexora is available.\n\nCurrent Version: %@\nLatest Version: %@\n\nClick “Update Automatically via Sparkle” to download and install this release.",
            .updateWithSparkle: "Update Automatically via Sparkle",
            .updateLater: "Later",
            .upToDateTitle: "You’re Up to Date",
            .upToDateMessage: "Nexora %@ is currently the latest available version. No update is required.",
            .updateCheckFailedTitle: "Unable to Check for Updates",
            .updateCheckFailedMessage: "Nexora could not retrieve update information at this time. Please check your network connection and try again.\n\nDetails: %@",
            .updateCheckUnavailable: "Update checks are currently unavailable. Please try again later.",
            .dashboard: "Dashboard",
            .diagnostics: "Diagnostics",
            .proxies: "Proxies",
            .routing: "Routing",
            .profiles: "Profiles",
            .connections: "Connections",
            .coreStatus: "Core Status",
            .quickEdit: "Quick Edit",
            .cancel: "Cancel",
            .confirm: "Confirm",
            .restartCore: "Restart Core",
            .startCore: "Start Core",
            .renameProfile: "Rename Profile",
            .profileName: "Profile Name",
            .rename: "Rename",
            .systemProxy: "System Proxy",
            .networkSpeed: "Network Speed",
            .networkDetection: "Network Detection",
            .networkDoctor: "Network Doctor",
            .runNetworkDoctor: "Run Network Doctor",
            .diagnosticSnapshot: "Diagnostic snapshot",
            .diagnosticExplanationTitle: "Diagnostic explanation",
            .diagnosticExplanationPlaceholder: "Run a network diagnosis to see what the checks mean and what to try next.",
            .diagnosticExplanationRules: "Diagnostic rules",
            .diagnosticExplanationModel: "Local model",
            .diagnosticExplanationEvidence: "Evidence",
            .diagnosticExplanationNextSteps: "Next steps",
            .diagnosticExplanationAIAction: "Explain with local AI",
            .diagnosticExplanationGenerating: "Preparing local explanation…",
            .diagnosticExplanationSnapshotHint: "Based on this diagnostic snapshot. Run again after the network changes.",
            .diagnosticExplanationPrivacyHint: "Local AI uses only redacted check results. Your configuration and logs are not uploaded.",
            .diagnosticExplanationUnsupportedSystem: "Local AI requires macOS 26 or later. The diagnostic rules remain available.",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence is off. Enable it in System Settings to use local AI; the diagnostic rules remain available.",
            .diagnosticExplanationModelNotReady: "The local model is not ready. Try again after macOS finishes preparing it.",
            .diagnosticExplanationDeviceIneligible: "This device cannot currently use the Apple Intelligence local model. The diagnostic rules remain available.",
            .diagnosticExplanationModelUnavailable: "The local model is unavailable. The diagnostic rules remain available.",
            .diagnosticExplanationFallback: "The local model did not finish. Showing the diagnostic rules.",
            .diagnosticExplanationStale: "Outdated snapshot",
            .diagnosticExplanationStaleHint: "The network state has changed. This is the previous diagnostic explanation; run a new diagnosis.",
            .networkDiagnosisHint: "Run a diagnosis to inspect route, DNS, ports, and external probes.",
            .diagnosticReadyHeadline: "Ready for diagnosis",
            .diagnosticBlockingHeadline: "Blocking layer detected",
            .diagnosticAttentionHeadline: "Route needs attention",
            .diagnosticCleanHeadline: "Route looks clean",
            .diagnosticReadyDetailFormat: "Network Doctor · %d",
            .diagnosticResultDetailFormat: "%@ · %d checks",
            .diagnosticChecks: "Checks",
            .diagnosticExit: "Exit",
            .portRadar: "Port Radar",
            .findings: "Findings",
            .dnsProbe: "DNS Probe",
            .endpointProbe: "Endpoint Probe",
            .diagnose: "Diagnose",
            .copyReport: "Copy Report",
            .suggestedAction: "Suggested Action",
            .detectingEgress: "Detecting Egress",
            .directEgress: "Direct Egress",
            .proxyEgress: "Proxy Egress",
            .systemTunnelEgress: "System Tunnel",
            .unavailableEgress: "Unavailable",
            .outboundMode: "Outbound Mode",
            .trafficUsage: "Traffic Usage",
            .intranetIP: "Intranet IP",
            .options: "Options",
            .rule: "Rule",
            .global: "Global",
            .direct: "Direct",
            .upload: "Upload",
            .download: "Download",
            .search: "Search", .closeAll: "Close All", .refresh: "Refresh",
            .noConnections: "No Connections", .host: "Host", .chain: "Chain",
            .closeConnection: "Close Connection", .ready: "Ready",
            .errors: "Errors", .warnings: "Warnings",
            .stopped: "Stopped", .connected: "Connected",
            .coreRunning: "Core Running", .nodes: "nodes", .allNodes: "All",
            .selectedOnly: "Selected", .untested: "Untested", .slowNodes: "Slow",
            .noProxyNodes: "No Proxy Nodes Available",
            .validateAll: "Validate All", .openManagedFolder: "Open Managed Folder",
            .importYAML: "Import YAML", .importConfiguration: "Import Configuration",
            .noMatchingProfiles: "No Matching Profiles", .allProfiles: "All",
            .deleteProfile: "Delete Profile",
            .managedYAML: "Managed YAML", .running: "Running", .current: "Current",
            .managed: "Managed", .selected: "Selected", .use: "Use", .validate: "Validate",
            .notValidated: "Not Checked", .checking: "Checking", .valid: "Valid",
            .invalid: "Needs Fix",
            .revealInFinder: "Reveal in Finder", .delete: "Delete", .delayTest: "Delay Test",
            .automatic: "Automatic", .collapse: "Collapse",
            .expand: "Expand", .addRule: "Add Rule", .saving: "Saving",
            .domainRouting: "Domain Routing", .deleteRule: "Delete Rule",
            .noMatchingRoutingRules: "No Matching Routing Rules",
            .addDomainHint: "Add a domain to choose VPN or Direct routing",
            .start: "Start", .pause: "Pause",
            .tab: "Tab", .list: "List", .selector: "Selector", .proxy: "Proxy",
            .urlTest: "URL Test", .fallback: "Fallback", .loadBalance: "Load Balance",
            .profileStorageFormat: "Profile: %@ · saved separately from its YAML",
            .selectProfileBeforeRules: "Select a managed profile before adding rules",
            .ruleCountSingular: "%d rule", .ruleCountPlural: "%d rules",
            .routingExplanation: "VPN rules use the profile's primary selectable proxy group. Direct rules bypass Mihomo's proxy chain.",
            .poweredByMihomo: "Powered by Mihomo",
            .ok: "OK", .renameMenuBarNote: "This name is also shown in the menu bar panel.",
            .restartActiveExplanation: "Mihomo and the active VPN session will restart, then restore the current outbound mode.",
            .restartControllerExplanation: "Mihomo's controller-only session will restart without enabling the system VPN.",
            .startControllerExplanation: "Mihomo is stopped. Confirm to start the core in controller-only mode.",
            .deleteProfileFormat: "Delete %@?", .profile: "Profile",
            .deleteProfileExplanation: "The managed YAML copy and its saved routing overrides will be removed.",
        ],
        .simplifiedChinese: [
            .clearSearch: "清空搜索",
            .websiteComparisonTitle: "网址连接对比",
            .websiteComparisonHint: "输入遇到问题的网址，对比直连与当前 Nexora 路线。",
            .websiteURL: "目标网址",
            .websiteURLPlaceholder: "example.com 或 https://example.com/path",
            .websiteCompare: "检测网址",
            .websiteDirectRoute: "直连",
            .websiteNexoraRoute: "经 Nexora",
            .websiteDirectHint: "绕过系统代理设置。",
            .websiteNexoraHint: "遵循当前模式和分流规则，也可能仍为直连。",
            .websiteTunnelWarning: "存在系统隧道：两种请求都可能经过隧道，“直连”不能代表关闭 VPN 后的结果。",
            .websiteInvalidURL: "请输入有效的 HTTP(S) 网址，不能包含内嵌的账号或密码。",
            .websiteProxyInactive: "未检测到运行中的 Nexora 代理。",
            .websiteResponseReceived: "已收到服务器响应。",
            .websiteHTTPRestricted: "服务器已响应；请检查登录、访问权限或网站状态。",
            .websiteDNSFailure: "域名解析失败。",
            .websiteConnectionFailure: "无法建立连接。",
            .websiteTLSFailure: "HTTPS 证书或安全握手失败。",
            .websiteTimeout: "请求超时。",
            .websiteRequestFailure: "请求未完成，请重试。",
            .websiteProxyAuthentication: "代理要求身份验证。",
            .websiteCancelled: "已取消，可重新检测。",
            .websiteStaleHint: "网络设置或网址已变，请重新检测。",
            .websiteDNSTime: "DNS 解析",
            .websiteTotalTime: "总耗时",
            .websiteWaiting: "等待检测",
            .websiteCopyResults: "复制对比结果",
            .profileDownloadNotConfiguration: "服务器返回的内容不是 Clash/Mihomo YAML 配置。请从服务商后台复制 Clash/Mihomo 格式的订阅链接。",
            .profileTrafficSnapshot: "配置快照",
            .profileTrafficSnapshotHelpFormat: "配置快照时间：%@。通过订阅链接导入可刷新配额。",
            .profileTrafficLocal: "本地配置",
            .profileTrafficLocalHelp: "此本地 YAML 未包含配额信息。通过订阅链接导入可获取服务商流量信息。",
            .profileTrafficNotReported: "未返回配额",
            .profileTrafficNotReportedHelp: "订阅服务器没有提供流量配额信息。",
            .profileTrafficRefreshFailed: "刷新失败，保留上次流量数据。",
            .profileTrafficLeftGBFormat: "剩余 %@ GB",
            .profileTrafficLeftPercentFormat: "剩余 %@",
            .profileTrafficUnavailable: "暂无流量信息",
            .profileTrafficUpdatedFormat: "订阅流量更新于 %@",
            .importFromFile: "从文件导入",
            .importFileHint: "选择或拖入 YAML 文件",
            .importFromURL: "从网址导入",
            .importURLHint: "粘贴 Mihomo YAML 配置的网址。",
            .profileURL: "配置网址",
            .downloadAndImport: "下载并导入",
            .importingProfile: "正在导入…",
            .invalidProfileURL: "请输入有效的 http:// 或 https:// 网址。",
            .profileDownloadHTTPErrorFormat: "下载失败（HTTP %d）。",
            .profileDownloadInvalidResponse: "服务器未返回有效的 HTTP 响应。",
            .profileDownloadEmpty: "下载的配置为空。",
            .glassAppearance: "玻璃与模糊",
            .blurStrength: "模糊程度",
            .glassBlurHint: "数值越高，窗口背景和卡片的磨砂感越强。文字和按钮始终清晰。",
            .glassAccessibilityHint: "macOS 的“降低透明度”设置优先于这些选项。",
            .resetGlassAppearance: "恢复默认",

            .menuQuickAccess: "快捷面板",
            .menuNodes: "节点",
            .noMatchingNodes: "没有匹配的节点",
            .menuSelectedNode: "已选节点",
            .updating: "正在更新…",
            .settings: "设置", .settingsSubtitle: "个性化 Nexora 并查看应用信息。",
            .appearance: "外观", .colorScheme: "配色方案", .accentColor: "强调色", .reduceMotion: "减少动态效果", .system: "跟随系统",
            .light: "浅色", .dark: "深色", .language: "语言", .systemDefault: "系统默认",
            .latencyTesting: "延迟测试", .latencyTestURL: "测试 URL",
            .latencyTestTimeout: "超时时间",
            .about: "关于", .version: "版本", .engine: "核心", .legalNotice: "法律声明",
            .permittedUse: "允许用途", .yourResponsibility: "您的责任",
            .noWarranty: "无担保与责任限制", .thirdPartyServices: "第三方服务",
            .indemnification: "赔偿责任",
            .disclaimerPurpose: "Nexora 仅供合法的教育、学术、互操作性及安全研究用途。",
            .disclaimerResponsibility: "您有责任取得所有必要授权，并遵守适用的法律、法规、许可、网络政策及第三方条款。不得使用本软件进行未经授权的访问、干扰服务、规避合法限制、侵犯权利或协助违法活动。",
            .disclaimerLiability: "在适用法律允许的最大范围内，本软件按“现状”和“可用状态”提供，不作任何担保。开发者及贡献者不对因本软件或其使用产生的任何直接、间接、附带、特殊、惩罚性或后果性损失承担责任，包括数据、隐私、利润、服务、账户、设备或网络可用性的损失。",
            .disclaimerThirdParties: "Mihomo、网络服务商、订阅服务商、网站及其他第三方组件或服务均独立于 Nexora，其可用性、安全性、内容、行为及条款不受开发者控制。",
            .disclaimerIndemnity: "在适用法律允许的最大范围内，您同意就因您的使用、误用、分发、配置或违反法律及第三方权利而产生的索赔、损害、处罚、责任、费用及合理法律费用，为开发者及贡献者进行抗辩、赔偿并使其免受损害。",
            .update: "更新",
            .checkForUpdates: "检查更新",
            .checkingForUpdates: "正在检查更新…",
            .updateAvailableTitle: "发现可用更新",
            .updateAvailableMessage: "检测到 Nexora 有新的正式版本可用。\n\n当前版本：%@\n最新版本：%@\n\n点击“通过 Sparkle 自动更新”即可自动下载并安装此版本。",
            .updateWithSparkle: "通过 Sparkle 自动更新",
            .updateLater: "稍后更新",
            .upToDateTitle: "当前已是最新版本",
            .upToDateMessage: "您当前使用的 Nexora %@ 已是公开发布的最新版本，无需更新。",
            .updateCheckFailedTitle: "检查更新失败",
            .updateCheckFailedMessage: "暂时无法获取最新版本信息，请确认网络连接正常后重试。\n\n详细信息：%@",
            .updateCheckUnavailable: "当前无法启动更新检查，请稍后重试。",
            .dashboard: "仪表盘", .diagnostics: "诊断",
            .proxies: "代理", .routing: "路由",
            .profiles: "配置", .connections: "连接",
            .coreStatus: "核心状态", .quickEdit: "快速编辑",
            .cancel: "取消", .confirm: "确认", .restartCore: "重启核心", .startCore: "启动核心",
            .renameProfile: "重命名配置", .profileName: "配置名称", .rename: "重命名",
            .systemProxy: "系统代理", .networkSpeed: "网络速度",
            .networkDetection: "网络检测", .outboundMode: "出站模式",
            .networkDoctor: "网络诊断", .runNetworkDoctor: "运行网络诊断",
            .diagnosticSnapshot: "诊断快照",
            .diagnosticExplanationTitle: "诊断解释",
            .diagnosticExplanationPlaceholder: "先运行网络诊断，查看检测结果说明和建议操作。",
            .diagnosticExplanationRules: "规则解释",
            .diagnosticExplanationModel: "本机模型",
            .diagnosticExplanationEvidence: "检测依据",
            .diagnosticExplanationNextSteps: "下一步",
            .diagnosticExplanationAIAction: "本机 AI 解释",
            .diagnosticExplanationGenerating: "正在生成本机解释…",
            .diagnosticExplanationSnapshotHint: "解释基于本次诊断快照；网络变化后请重新诊断。",
            .diagnosticExplanationPrivacyHint: "本机 AI 只处理脱敏检测结果，不上传配置或日志。",
            .diagnosticExplanationUnsupportedSystem: "本机 AI 需要 macOS 26 或更高版本，当前仍可查看规则解释。",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence 尚未启用。可在系统设置中启用，当前仍可查看规则解释。",
            .diagnosticExplanationModelNotReady: "本机模型尚未准备好，请在 macOS 完成准备后重试。",
            .diagnosticExplanationDeviceIneligible: "当前设备无法使用 Apple Intelligence 本机模型，仍可查看规则解释。",
            .diagnosticExplanationModelUnavailable: "本机模型当前不可用，仍可查看规则解释。",
            .diagnosticExplanationFallback: "本机模型未完成，继续显示规则解释。",
            .diagnosticExplanationStale: "过期快照",
            .diagnosticExplanationStaleHint: "网络状态已变化，这是上次诊断解释，请重新诊断。",
            .networkDiagnosisHint: "运行诊断以检查路由、DNS、端口和外部探测点。",
            .diagnosticReadyHeadline: "已准备诊断", .diagnosticBlockingHeadline: "检测到阻断环节",
            .diagnosticAttentionHeadline: "路由需要处理", .diagnosticCleanHeadline: "路由状态正常",
            .diagnosticReadyDetailFormat: "网络诊断 · %d",
            .diagnosticResultDetailFormat: "%@ · %d 项检查",
            .diagnosticChecks: "检查", .diagnosticExit: "出口",
            .portRadar: "端口雷达", .findings: "发现项",
            .dnsProbe: "DNS 探测", .endpointProbe: "端点探测", .diagnose: "诊断",
            .copyReport: "复制报告", .suggestedAction: "建议操作",
            .detectingEgress: "正在检测出口", .directEgress: "直连出口",
            .proxyEgress: "代理出口", .systemTunnelEgress: "系统隧道出口",
            .unavailableEgress: "出口不可用",
            .trafficUsage: "流量使用", .intranetIP: "内网 IP", .options: "选项",
            .rule: "规则", .global: "全局", .direct: "直连", .upload: "上传", .download: "下载",
            .search: "搜索", .closeAll: "全部关闭", .refresh: "刷新", .noConnections: "暂无连接",
            .host: "主机", .chain: "链路", .closeConnection: "关闭连接",
            .ready: "就绪", .errors: "错误",
            .warnings: "警告", .stopped: "已停止",
            .connected: "已连接",
            .coreRunning: "核心运行中", .nodes: "个节点", .allNodes: "全部",
            .selectedOnly: "已选", .untested: "未测速", .slowNodes: "慢节点",
            .noProxyNodes: "没有可用代理节点",
            .validateAll: "全部验证", .openManagedFolder: "打开托管文件夹", .importYAML: "导入 YAML",
            .importConfiguration: "导入配置", .noMatchingProfiles: "没有匹配的配置",
            .allProfiles: "全部", .deleteProfile: "删除配置", .managedYAML: "托管 YAML", .running: "运行中",
            .current: "当前", .managed: "已托管", .selected: "已选择", .use: "使用",
            .validate: "验证", .revealInFinder: "在访达中显示", .delete: "删除",
            .notValidated: "未检查", .checking: "检查中", .valid: "有效", .invalid: "需修复",
            .delayTest: "延迟测试", .automatic: "自动",
            .collapse: "收起", .expand: "展开", .addRule: "添加规则", .saving: "保存中",
            .domainRouting: "域名路由", .deleteRule: "删除规则",
            .noMatchingRoutingRules: "没有匹配的路由规则",
            .addDomainHint: "添加域名并选择通过 VPN 或直连",
            .start: "启动", .pause: "暂停",
            .tab: "标签", .list: "列表", .selector: "选择器", .proxy: "代理",
            .urlTest: "自动测速", .fallback: "故障转移", .loadBalance: "负载均衡",
            .profileStorageFormat: "配置：%@ · 独立保存，不修改原 YAML",
            .selectProfileBeforeRules: "添加规则前请先选择一个托管配置",
            .ruleCountSingular: "%d 条规则", .ruleCountPlural: "%d 条规则",
            .routingExplanation: "VPN 规则使用配置中的主要可选代理组。直连规则会绕过 Mihomo 的代理链。",
            .poweredByMihomo: "由 Mihomo 驱动",
            .ok: "确定", .renameMenuBarNote: "新名称也会显示在菜单栏面板中。",
            .restartActiveExplanation: "Mihomo 和当前 VPN 会话将重新启动，并恢复当前出站模式。",
            .restartControllerExplanation: "Mihomo 控制器会重启，但不会启用系统 VPN。",
            .startControllerExplanation: "Mihomo 当前已停止。确认后将以仅控制器模式启动核心。",
            .deleteProfileFormat: "删除“%@”？", .profile: "配置",
            .deleteProfileExplanation: "托管的 YAML 副本及其保存的路由规则将被删除。",
        ],
        .traditionalChinese: [
            .clearSearch: "清空搜尋",
            .websiteComparisonTitle: "網址連線對比",
            .websiteComparisonHint: "輸入有問題的網址，對比直連與目前 Nexora 路線。",
            .websiteURL: "目標網址",
            .websiteURLPlaceholder: "example.com 或 https://example.com/path",
            .websiteCompare: "檢測網址",
            .websiteDirectRoute: "直連",
            .websiteNexoraRoute: "經 Nexora",
            .websiteDirectHint: "略過系統代理設定。",
            .websiteNexoraHint: "遵循目前模式與分流規則，也可能仍為直連。",
            .websiteTunnelWarning: "存在系統通道：兩種請求都可能經過通道，「直連」不能代表關閉 VPN 後的結果。",
            .websiteInvalidURL: "請輸入有效的 HTTP(S) 網址，不能包含內嵌的帳號或密碼。",
            .websiteProxyInactive: "未偵測到執行中的 Nexora 代理。",
            .websiteResponseReceived: "已收到伺服器回應。",
            .websiteHTTPRestricted: "伺服器已回應；請檢查登入、存取權限或網站狀態。",
            .websiteDNSFailure: "網域名稱解析失敗。",
            .websiteConnectionFailure: "無法建立連線。",
            .websiteTLSFailure: "HTTPS 憑證或安全交握失敗。",
            .websiteTimeout: "請求逾時。",
            .websiteRequestFailure: "請求未完成，請重試。",
            .websiteProxyAuthentication: "代理要求身分驗證。",
            .websiteCancelled: "已取消，可重新檢測。",
            .websiteStaleHint: "網路設定或網址已變，請重新檢測。",
            .websiteDNSTime: "DNS 解析",
            .websiteTotalTime: "總耗時",
            .websiteWaiting: "等待檢測",
            .websiteCopyResults: "複製對比結果",
            .profileDownloadNotConfiguration: "伺服器回傳的內容不是 Clash/Mihomo YAML 設定。請從服務商後台複製 Clash/Mihomo 格式的訂閱連結。",
            .profileTrafficSnapshot: "設定快照",
            .profileTrafficSnapshotHelpFormat: "設定快照時間：%@。透過訂閱連結匯入可更新配額。",
            .profileTrafficLocal: "本機設定",
            .profileTrafficLocalHelp: "此本機 YAML 未包含配額資訊。透過訂閱連結匯入可取得服務商流量資訊。",
            .profileTrafficNotReported: "未回傳配額",
            .profileTrafficNotReportedHelp: "訂閱伺服器沒有提供流量配額資訊。",
            .profileTrafficRefreshFailed: "更新失敗，保留上次流量資料。",
            .profileTrafficLeftGBFormat: "剩餘 %@ GB",
            .profileTrafficLeftPercentFormat: "剩餘 %@",
            .profileTrafficUnavailable: "暫無流量資訊",
            .profileTrafficUpdatedFormat: "訂閱流量更新於 %@",
            .importFromFile: "從檔案匯入",
            .importFileHint: "選擇或拖入 YAML 檔案",
            .importFromURL: "從網址匯入",
            .importURLHint: "貼上 Mihomo YAML 設定的網址。",
            .profileURL: "設定網址",
            .downloadAndImport: "下載並匯入",
            .importingProfile: "正在匯入…",
            .invalidProfileURL: "請輸入有效的 http:// 或 https:// 網址。",
            .profileDownloadHTTPErrorFormat: "下載失敗（HTTP %d）。",
            .profileDownloadInvalidResponse: "伺服器未傳回有效的 HTTP 回應。",
            .profileDownloadEmpty: "下載的設定為空。",
            .glassAppearance: "玻璃與模糊",
            .blurStrength: "模糊程度",
            .glassBlurHint: "數值越高，視窗背景和卡片的磨砂感越強。文字和按鈕保持清晰。",
            .glassAccessibilityHint: "macOS 的「降低透明度」設定優先於這些選項。",
            .resetGlassAppearance: "回復預設",

            .menuQuickAccess: "快捷面板",
            .menuNodes: "節點",
            .noMatchingNodes: "沒有符合的節點",
            .menuSelectedNode: "已選節點",
            .updating: "正在更新…",
            .settings: "設定", .settingsSubtitle: "個人化 Nexora 並檢視應用程式資訊。",
            .appearance: "外觀", .colorScheme: "配色方案", .accentColor: "強調色", .reduceMotion: "減少動態效果", .system: "跟隨系統",
            .light: "淺色", .dark: "深色", .language: "語言", .systemDefault: "系統預設",
            .latencyTesting: "延遲測試", .latencyTestURL: "測試 URL",
            .latencyTestTimeout: "逾時時間",
            .about: "關於", .version: "版本", .engine: "核心", .legalNotice: "法律聲明",
            .permittedUse: "允許用途", .yourResponsibility: "您的責任",
            .noWarranty: "無擔保與責任限制", .thirdPartyServices: "第三方服務",
            .indemnification: "賠償責任",
            .disclaimerPurpose: "Nexora 僅供合法的教育、學術、互通性及安全研究用途。",
            .disclaimerResponsibility: "您有責任取得所有必要授權，並遵守適用的法律、法規、授權、網路政策及第三方條款。不得使用本軟體進行未經授權的存取、干擾服務、規避合法限制、侵犯權利或協助違法活動。",
            .disclaimerLiability: "在適用法律允許的最大範圍內，本軟體按「現狀」及「可用狀態」提供，不作任何擔保。開發者及貢獻者不對因本軟體或其使用所產生的任何直接、間接、附帶、特殊、懲罰性或後果性損失承擔責任。",
            .disclaimerThirdParties: "Mihomo、網路供應商、訂閱供應商、網站及其他第三方元件或服務均獨立於 Nexora，其可用性、安全性、內容、行為及條款不受開發者控制。",
            .disclaimerIndemnity: "在適用法律允許的最大範圍內，您同意就因您的使用、誤用、散佈、設定或違反法律及第三方權利而產生的索賠、損害、處罰、責任、費用及合理法律費用，為開發者及貢獻者進行抗辯、賠償並使其免受損害。",
            .update: "更新",
            .checkForUpdates: "檢查更新",
            .checkingForUpdates: "正在檢查更新…",
            .updateAvailableTitle: "發現可用更新",
            .updateAvailableMessage: "偵測到 Nexora 有新的正式版本可用。\n\n目前版本：%@\n最新版本：%@\n\n按一下「透過 Sparkle 自動更新」即可自動下載並安裝此版本。",
            .updateWithSparkle: "透過 Sparkle 自動更新",
            .updateLater: "稍後更新",
            .upToDateTitle: "目前已是最新版本",
            .upToDateMessage: "您目前使用的 Nexora %@ 已是公開發佈的最新版本，無須更新。",
            .updateCheckFailedTitle: "檢查更新失敗",
            .updateCheckFailedMessage: "暫時無法取得最新版本資訊，請確認網路連線正常後重試。\n\n詳細資訊：%@",
            .updateCheckUnavailable: "目前無法啟動更新檢查，請稍後重試。",
            .dashboard: "儀表板", .diagnostics: "診斷",
            .proxies: "代理", .routing: "路由",
            .profiles: "設定檔", .connections: "連線",
            .coreStatus: "核心狀態", .quickEdit: "快速編輯",
            .cancel: "取消", .confirm: "確認", .restartCore: "重新啟動核心", .startCore: "啟動核心",
            .renameProfile: "重新命名設定檔", .profileName: "設定檔名稱", .rename: "重新命名",
            .systemProxy: "系統代理", .networkSpeed: "網路速度",
            .networkDetection: "網路偵測", .outboundMode: "出站模式",
            .networkDoctor: "網路診斷", .runNetworkDoctor: "執行網路診斷",
            .diagnosticSnapshot: "診斷快照",
            .diagnosticExplanationTitle: "診斷解釋",
            .diagnosticExplanationPlaceholder: "先執行網路診斷，查看檢測結果說明與建議操作。",
            .diagnosticExplanationRules: "規則解釋",
            .diagnosticExplanationModel: "本機模型",
            .diagnosticExplanationEvidence: "檢測依據",
            .diagnosticExplanationNextSteps: "下一步",
            .diagnosticExplanationAIAction: "本機 AI 解釋",
            .diagnosticExplanationGenerating: "正在產生本機解釋…",
            .diagnosticExplanationSnapshotHint: "解釋根據本次診斷快照；網路變更後請重新診斷。",
            .diagnosticExplanationPrivacyHint: "本機 AI 只處理去識別化的檢測結果，不上傳設定或記錄。",
            .diagnosticExplanationUnsupportedSystem: "本機 AI 需要 macOS 26 或以上版本，目前仍可查看規則解釋。",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence 尚未啟用。可在系統設定中啟用，目前仍可查看規則解釋。",
            .diagnosticExplanationModelNotReady: "本機模型尚未準備好，請在 macOS 完成準備後再試。",
            .diagnosticExplanationDeviceIneligible: "目前裝置無法使用 Apple Intelligence 本機模型，仍可查看規則解釋。",
            .diagnosticExplanationModelUnavailable: "本機模型目前無法使用，仍可查看規則解釋。",
            .diagnosticExplanationFallback: "本機模型未完成，繼續顯示規則解釋。",
            .diagnosticExplanationStale: "過期快照",
            .diagnosticExplanationStaleHint: "網路狀態已變更，這是上次的診斷解釋，請重新診斷。",
            .networkDiagnosisHint: "執行診斷以檢查路由、DNS、連接埠和外部探測點。",
            .diagnosticReadyHeadline: "已準備診斷", .diagnosticBlockingHeadline: "偵測到阻斷環節",
            .diagnosticAttentionHeadline: "路由需要處理", .diagnosticCleanHeadline: "路由狀態正常",
            .diagnosticReadyDetailFormat: "網路診斷 · %d",
            .diagnosticResultDetailFormat: "%@ · %d 項檢查",
            .diagnosticChecks: "檢查", .diagnosticExit: "出口",
            .portRadar: "連接埠雷達", .findings: "發現項",
            .dnsProbe: "DNS 探測", .endpointProbe: "端點探測", .diagnose: "診斷",
            .copyReport: "複製報告", .suggestedAction: "建議操作",
            .detectingEgress: "正在偵測出口", .directEgress: "直連出口",
            .proxyEgress: "代理出口", .systemTunnelEgress: "系統隧道出口",
            .unavailableEgress: "出口不可用",
            .trafficUsage: "流量使用", .intranetIP: "內網 IP", .options: "選項",
            .rule: "規則", .global: "全域", .direct: "直連", .upload: "上傳", .download: "下載",
            .search: "搜尋", .closeAll: "全部關閉", .refresh: "重新整理", .noConnections: "暫無連線",
            .host: "主機", .chain: "鏈路", .closeConnection: "關閉連線",
            .ready: "就緒", .errors: "錯誤",
            .warnings: "警告", .stopped: "已停止",
            .connected: "已連線",
            .coreRunning: "核心執行中", .nodes: "個節點", .allNodes: "全部",
            .selectedOnly: "已選", .untested: "未測速", .slowNodes: "慢節點",
            .noProxyNodes: "沒有可用代理節點",
            .validateAll: "全部驗證", .openManagedFolder: "開啟託管資料夾", .importYAML: "匯入 YAML",
            .importConfiguration: "匯入設定", .noMatchingProfiles: "沒有符合的設定檔",
            .allProfiles: "全部", .deleteProfile: "刪除設定檔", .managedYAML: "託管 YAML", .running: "執行中",
            .current: "目前", .managed: "已託管", .selected: "已選取", .use: "使用",
            .validate: "驗證", .revealInFinder: "在 Finder 中顯示", .delete: "刪除",
            .notValidated: "未檢查", .checking: "檢查中", .valid: "有效", .invalid: "需修復",
            .delayTest: "延遲測試", .automatic: "自動",
            .collapse: "收合", .expand: "展開", .addRule: "新增規則", .saving: "儲存中",
            .domainRouting: "網域路由", .deleteRule: "刪除規則",
            .noMatchingRoutingRules: "沒有符合的路由規則",
            .addDomainHint: "新增網域並選擇透過 VPN 或直接連線",
            .start: "啟動", .pause: "暫停",
            .tab: "分頁", .list: "列表", .selector: "選擇器", .proxy: "代理",
            .urlTest: "自動測速", .fallback: "故障轉移", .loadBalance: "負載平衡",
            .profileStorageFormat: "設定檔：%@ · 獨立儲存，不修改原 YAML",
            .selectProfileBeforeRules: "新增規則前請先選擇一個託管設定檔",
            .ruleCountSingular: "%d 條規則", .ruleCountPlural: "%d 條規則",
            .routingExplanation: "VPN 規則使用設定檔中的主要可選代理群組。直連規則會略過 Mihomo 的代理鏈。",
            .poweredByMihomo: "由 Mihomo 驅動",
            .ok: "確定", .renameMenuBarNote: "新名稱也會顯示在選單列面板中。",
            .restartActiveExplanation: "Mihomo 與目前的 VPN 工作階段將重新啟動，並恢復目前的出站模式。",
            .restartControllerExplanation: "Mihomo 控制器將重新啟動，但不會啟用系統 VPN。",
            .startControllerExplanation: "Mihomo 目前已停止。確認後將以僅控制器模式啟動核心。",
            .deleteProfileFormat: "刪除「%@」？", .profile: "設定檔",
            .deleteProfileExplanation: "託管的 YAML 副本及其已儲存的路由規則將被刪除。",
        ],
        .japanese: [
            .clearSearch: "検索をクリア",
            .websiteComparisonTitle: "ウェブ接続の比較",
            .websiteComparisonHint: "問題のある URL を入力し、直接接続と現在の Nexora 経路を比較します。",
            .websiteURL: "ウェブサイト URL",
            .websiteURLPlaceholder: "example.com または https://example.com/path",
            .websiteCompare: "接続を比較",
            .websiteDirectRoute: "直接接続",
            .websiteNexoraRoute: "Nexora 経由",
            .websiteDirectHint: "システムのプロキシ設定を使用しません。",
            .websiteNexoraHint: "現在のモードとルールに従います。直接接続になる場合もあります。",
            .websiteTunnelWarning: "システムトンネルが有効です。両方の要求がトンネルを通る場合があり、VPN を切った状態とは異なります。",
            .websiteInvalidURL: "ユーザー名やパスワードを含まない有効な HTTP(S) URL を入力してください。",
            .websiteProxyInactive: "実行中の Nexora プロキシがありません。",
            .websiteResponseReceived: "サーバーが応答しました。",
            .websiteHTTPRestricted: "サーバーが応答しました。ログイン、アクセス権限、サイトの状態を確認してください。",
            .websiteDNSFailure: "DNS 名前解決に失敗しました。",
            .websiteConnectionFailure: "接続を確立できませんでした。",
            .websiteTLSFailure: "HTTPS 証明書または安全なハンドシェイクに失敗しました。",
            .websiteTimeout: "要求がタイムアウトしました。",
            .websiteRequestFailure: "要求が完了しませんでした。再試行してください。",
            .websiteProxyAuthentication: "プロキシ認証が必要です。",
            .websiteCancelled: "キャンセルしました。再度比較できます。",
            .websiteStaleHint: "ネットワーク設定または URL が変わりました。再度比較してください。",
            .websiteDNSTime: "DNS",
            .websiteTotalTime: "合計",
            .websiteWaiting: "検査待ち",
            .websiteCopyResults: "比較結果をコピー",
            .profileDownloadNotConfiguration: "サーバーから Clash/Mihomo の YAML 設定が返されませんでした。提供元から Clash/Mihomo 用の購読 URL をコピーしてください。",
            .profileTrafficSnapshot: "YAML の記録",
            .profileTrafficSnapshotHelpFormat: "%@ の YAML 記録。通信量を更新するには購読 URL から読み込んでください。",
            .profileTrafficLocal: "ローカル YAML",
            .profileTrafficLocalHelp: "この YAML に通信量情報はありません。購読 URL から読み込むと取得できます。",
            .profileTrafficNotReported: "通信量の提供なし",
            .profileTrafficNotReportedHelp: "購読サーバーから通信量情報が提供されていません。",
            .profileTrafficRefreshFailed: "更新に失敗しました。前回の通信量を表示しています。",
            .profileTrafficLeftGBFormat: "残り %@ GB",
            .profileTrafficLeftPercentFormat: "残り %@",
            .profileTrafficUnavailable: "通信量情報なし",
            .profileTrafficUpdatedFormat: "通信量の更新日時: %@",
            .importFromFile: "ファイルから読み込む",
            .importFileHint: "YAML ファイルを選択またはドロップ",
            .importFromURL: "URL から読み込む",
            .importURLHint: "Mihomo YAML 設定へのリンクを貼り付けてください。",
            .profileURL: "設定の URL",
            .downloadAndImport: "ダウンロードして読み込む",
            .importingProfile: "読み込み中…",
            .invalidProfileURL: "有効な http:// または https:// URL を入力してください。",
            .profileDownloadHTTPErrorFormat: "ダウンロードに失敗しました（HTTP %d）。",
            .profileDownloadInvalidResponse: "サーバーから有効な HTTP 応答がありません。",
            .profileDownloadEmpty: "ダウンロードした設定は空です。",
            .glassAppearance: "ガラスとぼかし",
            .blurStrength: "ぼかしの強さ",
            .glassBlurHint: "値を上げると背景とカードのすりガラス感が強くなります。文字とボタンは鮮明なままです。",
            .glassAccessibilityHint: "macOS の「透明度を下げる」設定が優先されます。",
            .resetGlassAppearance: "リセット",

            .menuQuickAccess: "クイックアクセス",
            .menuNodes: "ノード",
            .noMatchingNodes: "一致するノードがありません",
            .menuSelectedNode: "選択中のノード",
            .updating: "更新中…",
            .settings: "設定", .settingsSubtitle: "Nexora の外観と言語、アプリ情報を管理します。",
            .appearance: "外観", .colorScheme: "カラースキーム", .accentColor: "アクセントカラー", .reduceMotion: "視差効果を減らす", .system: "システム",
            .light: "ライト", .dark: "ダーク", .language: "言語", .systemDefault: "システム設定",
            .latencyTesting: "遅延テスト", .latencyTestURL: "テスト URL",
            .latencyTestTimeout: "タイムアウト",
            .about: "このアプリについて", .version: "バージョン", .engine: "エンジン",
            .legalNotice: "法的通知", .permittedUse: "許可された用途",
            .yourResponsibility: "利用者の責任", .noWarranty: "無保証および責任制限",
            .thirdPartyServices: "第三者サービス", .indemnification: "補償",
            .disclaimerPurpose: "Nexora は、合法的な教育、学術、相互運用性、およびセキュリティ研究のみを目的として提供されます。",
            .disclaimerResponsibility: "必要な許可を取得し、適用される法律、規制、ライセンス、ネットワークポリシー、第三者の規約を遵守する責任は利用者にあります。不正アクセス、サービス妨害、合法的制限の回避、権利侵害、違法行為への利用は禁止されています。",
            .disclaimerLiability: "適用法で認められる最大限の範囲で、本ソフトウェアは現状有姿かつ提供可能な状態で、いかなる保証もなく提供されます。開発者および貢献者は、本ソフトウェアまたはその利用に起因する直接的・間接的・付随的・特別・懲罰的・結果的損害について責任を負いません。",
            .disclaimerThirdParties: "Mihomo、ネットワーク事業者、購読事業者、ウェブサイト、その他の第三者コンポーネントやサービスは Nexora とは独立しており、その可用性、安全性、内容、行為、規約は開発者の管理外です。",
            .disclaimerIndemnity: "適用法で認められる最大限の範囲で、利用、誤用、配布、設定、法令または第三者の権利の違反に起因する請求、損害、罰則、責任、費用および合理的な弁護士費用から、開発者および貢献者を防御・補償することに同意します。",
            .update: "アップデート",
            .checkForUpdates: "アップデートを確認",
            .checkingForUpdates: "アップデートを確認中…",
            .updateAvailableTitle: "新しいアップデートがあります",
            .updateAvailableMessage: "Nexora の新しいリリース版が利用可能です。\n\n現在のバージョン：%@\n最新バージョン：%@\n\n「Sparkle で自動アップデート」をクリックすると、自動的にダウンロードしてインストールします。",
            .updateWithSparkle: "Sparkle で自動アップデート",
            .updateLater: "後で確認",
            .upToDateTitle: "お使いのバージョンは最新です",
            .upToDateMessage: "現在ご利用中の Nexora %@ は最新の公開バージョンです。アップデートの必要はありません。",
            .updateCheckFailedTitle: "アップデートを確認できません",
            .updateCheckFailedMessage: "現在アップデート情報を取得できません。ネットワーク接続をご確認のうえ、再試行してください。\n\n詳細：%@",
            .updateCheckUnavailable: "現在アップデート確認を開始できません。しばらくしてから再試行してください。",
            .dashboard: "ダッシュボード", .diagnostics: "診断",
            .proxies: "プロキシ",
            .routing: "ルーティング", .profiles: "プロファイル", .connections: "接続",
            .coreStatus: "コア状態", .quickEdit: "クイック編集", .cancel: "キャンセル",
            .confirm: "確認", .restartCore: "コアを再起動", .startCore: "コアを起動",
            .renameProfile: "プロファイル名を変更", .profileName: "プロファイル名", .rename: "名前を変更",
            .systemProxy: "システムプロキシ", .networkSpeed: "ネットワーク速度",
            .networkDetection: "ネットワーク検出", .outboundMode: "送信モード",
            .networkDoctor: "ネットワーク診断", .runNetworkDoctor: "ネットワーク診断を実行",
            .diagnosticSnapshot: "診断スナップショット",
            .diagnosticExplanationTitle: "診断の説明",
            .diagnosticExplanationPlaceholder: "ネットワーク診断を実行すると、検査結果の意味と次の手順を確認できます。",
            .diagnosticExplanationRules: "診断ルール",
            .diagnosticExplanationModel: "ローカルモデル",
            .diagnosticExplanationEvidence: "検出した情報",
            .diagnosticExplanationNextSteps: "次の手順",
            .diagnosticExplanationAIAction: "ローカル AI で説明",
            .diagnosticExplanationGenerating: "ローカルで説明を生成中…",
            .diagnosticExplanationSnapshotHint: "今回の診断結果に基づく説明です。ネットワークが変わったら再診断してください。",
            .diagnosticExplanationPrivacyHint: "ローカル AI は匿名化した検査結果のみを処理します。設定やログはアップロードされません。",
            .diagnosticExplanationUnsupportedSystem: "ローカル AI には macOS 26 以降が必要です。診断ルールによる説明は利用できます。",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence は無効です。システム設定で有効にするとローカル AI を利用できます。診断ルールによる説明は利用できます。",
            .diagnosticExplanationModelNotReady: "ローカルモデルは準備中です。macOS の準備が完了したら再試行してください。",
            .diagnosticExplanationDeviceIneligible: "このデバイスでは現在 Apple Intelligence のローカルモデルを利用できません。診断ルールによる説明は利用できます。",
            .diagnosticExplanationModelUnavailable: "ローカルモデルを利用できません。診断ルールによる説明を表示しています。",
            .diagnosticExplanationFallback: "ローカルモデルの処理が完了しませんでした。診断ルールによる説明を表示しています。",
            .diagnosticExplanationStale: "古いスナップショット",
            .diagnosticExplanationStaleHint: "ネットワークの状態が変わりました。前回の説明を表示しています。再診断してください。",
            .networkDiagnosisHint: "ルート、DNS、ポート、外部プローブを診断します。",
            .diagnosticReadyHeadline: "診断の準備完了", .diagnosticBlockingHeadline: "遮断箇所を検出",
            .diagnosticAttentionHeadline: "ルートに注意が必要", .diagnosticCleanHeadline: "ルートは正常です",
            .diagnosticReadyDetailFormat: "ネットワーク診断 · %d",
            .diagnosticResultDetailFormat: "%@ · %d 件",
            .diagnosticChecks: "チェック", .diagnosticExit: "出口",
            .portRadar: "ポートレーダー", .findings: "検出項目",
            .dnsProbe: "DNS プローブ", .endpointProbe: "エンドポイントプローブ", .diagnose: "診断",
            .copyReport: "レポートをコピー", .suggestedAction: "推奨操作",
            .detectingEgress: "出口を検出中", .directEgress: "直接出口",
            .proxyEgress: "プロキシ出口", .systemTunnelEgress: "システムトンネル",
            .unavailableEgress: "出口を取得できません",
            .trafficUsage: "通信量", .intranetIP: "ローカル IP", .options: "オプション",
            .rule: "ルール", .global: "グローバル", .direct: "直接", .upload: "アップロード", .download: "ダウンロード",
            .search: "検索", .closeAll: "すべて閉じる", .refresh: "更新", .noConnections: "接続なし",
            .host: "ホスト", .chain: "チェーン", .closeConnection: "接続を閉じる",
            .ready: "準備完了", .errors: "エラー",
            .warnings: "警告", .stopped: "停止中",
            .connected: "接続済み",
            .coreRunning: "コア実行中", .nodes: "ノード", .allNodes: "すべて",
            .selectedOnly: "選択済み", .untested: "未測定", .slowNodes: "低速",
            .noProxyNodes: "利用可能なプロキシノードがありません",
            .validateAll: "すべて検証", .openManagedFolder: "管理フォルダを開く", .importYAML: "YAML を読み込む",
            .importConfiguration: "設定を読み込む", .noMatchingProfiles: "一致するプロファイルがありません",
            .allProfiles: "すべて", .deleteProfile: "プロファイルを削除", .managedYAML: "管理対象 YAML", .running: "実行中",
            .current: "現在", .managed: "管理対象", .selected: "選択済み", .use: "使用",
            .validate: "検証", .revealInFinder: "Finder に表示", .delete: "削除",
            .notValidated: "未確認", .checking: "確認中", .valid: "有効", .invalid: "修正が必要",
            .delayTest: "遅延テスト", .automatic: "自動",
            .collapse: "折りたたむ", .expand: "展開", .addRule: "ルールを追加", .saving: "保存中",
            .domainRouting: "ドメインルーティング", .deleteRule: "ルールを削除",
            .noMatchingRoutingRules: "一致するルーティングルールがありません",
            .addDomainHint: "ドメインを追加して VPN または直接接続を選択",
            .start: "開始", .pause: "一時停止",
            .tab: "タブ", .list: "リスト", .selector: "セレクター", .proxy: "プロキシ",
            .urlTest: "URL テスト", .fallback: "フォールバック", .loadBalance: "負荷分散",
            .profileStorageFormat: "プロファイル：%@ · 元の YAML とは別に保存",
            .selectProfileBeforeRules: "ルールを追加する前に管理対象プロファイルを選択してください",
            .ruleCountSingular: "%d 件のルール", .ruleCountPlural: "%d 件のルール",
            .routingExplanation: "VPN ルールはプロファイルの主要な選択可能プロキシグループを使用します。直接接続ルールは Mihomo のプロキシチェーンを経由しません。",
            .poweredByMihomo: "Mihomo を搭載",
            .ok: "OK", .renameMenuBarNote: "新しい名前はメニューバーパネルにも表示されます。",
            .restartActiveExplanation: "Mihomo と有効な VPN セッションを再起動し、現在の送信モードを復元します。",
            .restartControllerExplanation: "システム VPN を有効にせず、Mihomo のコントローラーのみを再起動します。",
            .startControllerExplanation: "Mihomo は停止中です。確認するとコントローラーのみのモードで起動します。",
            .deleteProfileFormat: "「%@」を削除しますか？", .profile: "プロファイル",
            .deleteProfileExplanation: "管理対象の YAML コピーと保存済みルーティングルールが削除されます。",
        ],
        .french: [
            .clearSearch: "Effacer la recherche",
            .websiteComparisonTitle: "Comparaison de connexion web",
            .websiteComparisonHint: "Saisissez une URL pour comparer l’accès direct et le trajet Nexora actuel.",
            .websiteURL: "URL du site",
            .websiteURLPlaceholder: "example.com ou https://example.com/path",
            .websiteCompare: "Comparer le site",
            .websiteDirectRoute: "Direct",
            .websiteNexoraRoute: "Via Nexora",
            .websiteDirectHint: "Ignore les réglages du proxy système.",
            .websiteNexoraHint: "Respecte le mode et les règles actuels ; le trajet peut aussi être direct.",
            .websiteTunnelWarning: "Un tunnel système est actif : les deux requêtes peuvent l’emprunter. Direct ne simule pas la désactivation du VPN.",
            .websiteInvalidURL: "Saisissez une URL HTTP(S) valide sans identifiant ni mot de passe intégré.",
            .websiteProxyInactive: "Aucun proxy Nexora actif n’est disponible.",
            .websiteResponseReceived: "Le serveur a répondu.",
            .websiteHTTPRestricted: "Le serveur a répondu ; vérifiez la connexion au compte, les droits ou l’état du site.",
            .websiteDNSFailure: "Échec de la résolution DNS.",
            .websiteConnectionFailure: "Impossible d’établir la connexion.",
            .websiteTLSFailure: "Échec du certificat HTTPS ou de la négociation sécurisée.",
            .websiteTimeout: "Délai de la requête dépassé.",
            .websiteRequestFailure: "La requête n’a pas abouti. Réessayez.",
            .websiteProxyAuthentication: "Le proxy exige une authentification.",
            .websiteCancelled: "Annulé. Vous pouvez relancer la comparaison.",
            .websiteStaleHint: "L’URL ou les réglages réseau ont changé. Relancez la comparaison.",
            .websiteDNSTime: "DNS",
            .websiteTotalTime: "Total",
            .websiteWaiting: "En attente du test",
            .websiteCopyResults: "Copier les résultats",
            .profileDownloadNotConfiguration: "Le serveur n’a pas renvoyé de configuration YAML Clash/Mihomo. Copiez le lien d’abonnement Clash/Mihomo depuis votre fournisseur.",
            .profileTrafficSnapshot: "Instantané YAML",
            .profileTrafficSnapshotHelpFormat: "Instantané YAML du %@. Importez une URL d’abonnement pour actualiser le quota.",
            .profileTrafficLocal: "YAML local",
            .profileTrafficLocalHelp: "Ce YAML ne contient pas de quota. Importez l’URL d’abonnement pour obtenir les données du fournisseur.",
            .profileTrafficNotReported: "Quota non fourni",
            .profileTrafficNotReportedHelp: "Le serveur d’abonnement ne fournit pas de quota.",
            .profileTrafficRefreshFailed: "Échec de l’actualisation ; les dernières données sont conservées.",
            .profileTrafficLeftGBFormat: "%@ GB restants",
            .profileTrafficLeftPercentFormat: "%@ restants",
            .profileTrafficUnavailable: "Trafic indisponible",
            .profileTrafficUpdatedFormat: "Trafic mis à jour le %@",
            .importFromFile: "Importer un fichier",
            .importFileHint: "Choisir ou déposer un fichier YAML",
            .importFromURL: "Importer depuis une URL",
            .importURLHint: "Collez un lien vers une configuration YAML Mihomo.",
            .profileURL: "URL de la configuration",
            .downloadAndImport: "Télécharger et importer",
            .importingProfile: "Importation…",
            .invalidProfileURL: "Saisissez une URL http:// ou https:// valide.",
            .profileDownloadHTTPErrorFormat: "Échec du téléchargement (HTTP %d).",
            .profileDownloadInvalidResponse: "Le serveur n’a pas renvoyé de réponse HTTP valide.",
            .profileDownloadEmpty: "La configuration téléchargée est vide.",
            .glassAppearance: "Verre et flou",
            .blurStrength: "Intensité du flou",
            .glassBlurHint: "Une valeur élevée renforce le verre dépoli du fond et des cartes. Le texte et les commandes restent nets.",
            .glassAccessibilityHint: "Le réglage Réduire la transparence de macOS est prioritaire.",
            .resetGlassAppearance: "Réinitialiser",

            .menuQuickAccess: "Accès rapide",
            .menuNodes: "Nœuds",
            .noMatchingNodes: "Aucun nœud correspondant",
            .menuSelectedNode: "Nœud sélectionné",
            .updating: "Mise à jour…",
            .settings: "Réglages", .settingsSubtitle: "Personnalisez Nexora et consultez les informations de l’application.",
            .appearance: "Apparence", .colorScheme: "Thème", .accentColor: "Couleur d’accentuation", .reduceMotion: "Réduire les animations", .system: "Système",
            .light: "Clair", .dark: "Sombre", .language: "Langue", .systemDefault: "Langue du système",
            .latencyTesting: "Test de latence", .latencyTestURL: "URL de test",
            .latencyTestTimeout: "Délai d’attente",
            .about: "À propos", .version: "Version", .engine: "Moteur", .legalNotice: "Mentions légales",
            .permittedUse: "Usage autorisé", .yourResponsibility: "Votre responsabilité",
            .noWarranty: "Absence de garantie et limitation de responsabilité",
            .thirdPartyServices: "Services tiers", .indemnification: "Indemnisation",
            .disclaimerPurpose: "Nexora est fourni uniquement à des fins légales d’éducation, de recherche universitaire, d’interopérabilité et de sécurité.",
            .disclaimerResponsibility: "Vous êtes seul responsable de l’obtention des autorisations requises et du respect des lois, règlements, licences, politiques réseau et conditions de tiers applicables. Toute utilisation pour un accès non autorisé, une perturbation de service, un contournement illégal, une atteinte aux droits ou une activité illicite est interdite.",
            .disclaimerLiability: "Dans toute la mesure permise par la loi, le logiciel est fourni « en l’état » et « selon disponibilité », sans aucune garantie. Le développeur et les contributeurs ne répondent d’aucune perte directe, indirecte, accessoire, spéciale, punitive ou consécutive liée au logiciel ou à son utilisation.",
            .disclaimerThirdParties: "Mihomo, les fournisseurs de réseau ou d’abonnement, les sites web et les autres composants ou services tiers sont indépendants de Nexora. Leur disponibilité, sécurité, contenu, conduite et conditions échappent au contrôle du développeur.",
            .disclaimerIndemnity: "Dans toute la mesure permise par la loi, vous acceptez de défendre, indemniser et garantir le développeur et les contributeurs contre les réclamations, dommages, sanctions, responsabilités, frais et honoraires juridiques raisonnables résultant de votre utilisation, mauvaise utilisation, distribution, configuration ou violation de la loi ou des droits de tiers.",
            .update: "Mise à jour",
            .checkForUpdates: "Vérifier les mises à jour",
            .checkingForUpdates: "Recherche de mises à jour…",
            .updateAvailableTitle: "Mise à jour disponible",
            .updateAvailableMessage: "Une nouvelle version officielle de Nexora est disponible.\n\nVersion actuelle : %@\nDernière version : %@\n\nCliquez sur « Mettre à jour automatiquement via Sparkle » pour télécharger et installer cette version.",
            .updateWithSparkle: "Mettre à jour automatiquement via Sparkle",
            .updateLater: "Plus tard",
            .upToDateTitle: "Votre application est à jour",
            .upToDateMessage: "Nexora %@ est actuellement la dernière version publiée. Aucune mise à jour n’est nécessaire.",
            .updateCheckFailedTitle: "Échec de la vérification des mises à jour",
            .updateCheckFailedMessage: "Impossible de récupérer les informations de mise à jour pour le moment. Vérifiez votre connexion réseau et réessayez.\n\nDétails : %@",
            .updateCheckUnavailable: "La vérification des mises à jour est actuellement indisponible. Veuillez réessayer ultérieurement.",
            .dashboard: "Tableau de bord", .diagnostics: "Diagnostics",
            .proxies: "Proxy",
            .routing: "Routage", .profiles: "Profils", .connections: "Connexions",
            .coreStatus: "État du moteur",
            .quickEdit: "Modification rapide", .cancel: "Annuler", .confirm: "Confirmer",
            .restartCore: "Redémarrer le moteur", .startCore: "Démarrer le moteur",
            .renameProfile: "Renommer le profil", .profileName: "Nom du profil", .rename: "Renommer",
            .systemProxy: "Proxy système", .networkSpeed: "Vitesse du réseau",
            .networkDetection: "Détection du réseau", .outboundMode: "Mode de sortie",
            .networkDoctor: "Diagnostic réseau", .runNetworkDoctor: "Lancer le diagnostic réseau",
            .diagnosticSnapshot: "Instantané du diagnostic",
            .diagnosticExplanationTitle: "Explication du diagnostic",
            .diagnosticExplanationPlaceholder: "Lancez un diagnostic réseau pour comprendre les résultats et les prochaines étapes.",
            .diagnosticExplanationRules: "Règles de diagnostic",
            .diagnosticExplanationModel: "Modèle local",
            .diagnosticExplanationEvidence: "Éléments observés",
            .diagnosticExplanationNextSteps: "Étapes suivantes",
            .diagnosticExplanationAIAction: "Expliquer avec l’IA locale",
            .diagnosticExplanationGenerating: "Préparation de l’explication locale…",
            .diagnosticExplanationSnapshotHint: "Cette explication repose sur cet instantané. Relancez le diagnostic si le réseau change.",
            .diagnosticExplanationPrivacyHint: "L’IA locale traite uniquement les résultats anonymisés. Vos configurations et journaux ne sont pas envoyés.",
            .diagnosticExplanationUnsupportedSystem: "L’IA locale nécessite macOS 26 ou ultérieur. Les règles de diagnostic restent disponibles.",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence est désactivée. Activez-la dans Réglages Système pour utiliser l’IA locale ; les règles restent disponibles.",
            .diagnosticExplanationModelNotReady: "Le modèle local n’est pas prêt. Réessayez lorsque macOS a terminé sa préparation.",
            .diagnosticExplanationDeviceIneligible: "Cet appareil ne peut pas utiliser le modèle local Apple Intelligence actuellement. Les règles de diagnostic restent disponibles.",
            .diagnosticExplanationModelUnavailable: "Le modèle local est indisponible. Les règles de diagnostic restent disponibles.",
            .diagnosticExplanationFallback: "Le modèle local n’a pas terminé. Les règles de diagnostic sont affichées.",
            .diagnosticExplanationStale: "Instantané périmé",
            .diagnosticExplanationStaleHint: "L’état du réseau a changé. Cette explication vient du diagnostic précédent ; relancez le diagnostic.",
            .networkDiagnosisHint: "Lancez un diagnostic pour inspecter routage, DNS, ports et sondes externes.",
            .diagnosticReadyHeadline: "Prêt pour le diagnostic", .diagnosticBlockingHeadline: "Blocage détecté",
            .diagnosticAttentionHeadline: "Route à vérifier", .diagnosticCleanHeadline: "Route correcte",
            .diagnosticReadyDetailFormat: "Diagnostic réseau · %d",
            .diagnosticResultDetailFormat: "%@ · %d contrôles",
            .diagnosticChecks: "Contrôles", .diagnosticExit: "Sortie",
            .portRadar: "Radar des ports", .findings: "Constats",
            .dnsProbe: "Sonde DNS", .endpointProbe: "Sonde d’extrémité", .diagnose: "Diagnostiquer",
            .copyReport: "Copier le rapport", .suggestedAction: "Action suggérée",
            .detectingEgress: "Détection de sortie", .directEgress: "Sortie directe",
            .proxyEgress: "Sortie proxy", .systemTunnelEgress: "Tunnel système",
            .unavailableEgress: "Sortie indisponible",
            .trafficUsage: "Utilisation des données", .intranetIP: "IP locale", .options: "Options",
            .rule: "Règles", .global: "Global", .direct: "Direct", .upload: "Envoi", .download: "Réception",
            .search: "Rechercher", .closeAll: "Tout fermer", .refresh: "Actualiser",
            .noConnections: "Aucune connexion", .host: "Hôte", .chain: "Chaîne",
            .closeConnection: "Fermer la connexion", .ready: "Prêt", .errors: "Erreurs",
            .warnings: "Alertes", .stopped: "Arrêté",
            .connected: "Connecté",
            .coreRunning: "Moteur actif", .nodes: "nœuds", .allNodes: "Tous",
            .selectedOnly: "Sélectionnés", .untested: "Non testés", .slowNodes: "Lents",
            .noProxyNodes: "Aucun nœud proxy disponible",
            .validateAll: "Tout valider", .openManagedFolder: "Ouvrir le dossier géré",
            .importYAML: "Importer YAML", .importConfiguration: "Importer une configuration",
            .noMatchingProfiles: "Aucun profil correspondant", .allProfiles: "Tous",
            .deleteProfile: "Supprimer le profil",
            .managedYAML: "YAML géré", .running: "Actif", .current: "Actuel", .managed: "Géré",
            .selected: "Sélectionné", .use: "Utiliser", .validate: "Valider",
            .revealInFinder: "Afficher dans le Finder", .delete: "Supprimer",
            .notValidated: "Non vérifié", .checking: "Vérification", .valid: "Valide",
            .invalid: "À corriger",
            .delayTest: "Test de latence", .automatic: "Automatique",
            .collapse: "Réduire", .expand: "Développer", .addRule: "Ajouter une règle",
            .saving: "Enregistrement", .domainRouting: "Routage de domaine",
            .deleteRule: "Supprimer la règle", .noMatchingRoutingRules: "Aucune règle correspondante",
            .addDomainHint: "Ajoutez un domaine et choisissez VPN ou Direct",
            .start: "Démarrer", .pause: "Pause",
            .tab: "Onglet", .list: "Liste", .selector: "Sélecteur", .proxy: "Proxy",
            .urlTest: "Test URL", .fallback: "Repli", .loadBalance: "Répartition de charge",
            .profileStorageFormat: "Profil : %@ · enregistré séparément de son YAML",
            .selectProfileBeforeRules: "Sélectionnez un profil géré avant d'ajouter des règles",
            .ruleCountSingular: "%d règle", .ruleCountPlural: "%d règles",
            .routingExplanation: "Les règles VPN utilisent le groupe proxy sélectionnable principal du profil. Les règles directes contournent la chaîne proxy de Mihomo.",
            .poweredByMihomo: "Propulsé par Mihomo",
            .ok: "OK", .renameMenuBarNote: "Ce nom apparaît également dans le panneau de la barre des menus.",
            .restartActiveExplanation: "Mihomo et la session VPN active redémarreront, puis le mode de sortie actuel sera restauré.",
            .restartControllerExplanation: "La session contrôleur de Mihomo redémarrera sans activer le VPN système.",
            .startControllerExplanation: "Mihomo est arrêté. Confirmez pour démarrer le moteur en mode contrôleur uniquement.",
            .deleteProfileFormat: "Supprimer « %@ » ?", .profile: "Profil",
            .deleteProfileExplanation: "La copie YAML gérée et ses règles de routage enregistrées seront supprimées.",
        ],
        .russian: [
            .clearSearch: "Очистить поиск",
            .websiteComparisonTitle: "Сравнение подключения к сайту",
            .websiteComparisonHint: "Введите URL и сравните прямой доступ с текущим маршрутом Nexora.",
            .websiteURL: "URL сайта",
            .websiteURLPlaceholder: "example.com или https://example.com/path",
            .websiteCompare: "Проверить сайт",
            .websiteDirectRoute: "Напрямую",
            .websiteNexoraRoute: "Через Nexora",
            .websiteDirectHint: "Без системных настроек прокси.",
            .websiteNexoraHint: "Использует текущий режим и правила; маршрут также может быть прямым.",
            .websiteTunnelWarning: "Системный туннель активен: оба запроса могут идти через него. Прямой запрос не равнозначен отключению VPN.",
            .websiteInvalidURL: "Введите корректный HTTP(S) URL без встроенного имени пользователя и пароля.",
            .websiteProxyInactive: "Работающий прокси Nexora недоступен.",
            .websiteResponseReceived: "Сервер ответил.",
            .websiteHTTPRestricted: "Сервер ответил; проверьте вход, права доступа или состояние сайта.",
            .websiteDNSFailure: "Не удалось разрешить DNS-имя.",
            .websiteConnectionFailure: "Не удалось установить соединение.",
            .websiteTLSFailure: "Ошибка сертификата HTTPS или защищённого соединения.",
            .websiteTimeout: "Время ожидания истекло.",
            .websiteRequestFailure: "Запрос не завершён. Повторите попытку.",
            .websiteProxyAuthentication: "Прокси требует аутентификации.",
            .websiteCancelled: "Отменено. Проверку можно запустить снова.",
            .websiteStaleHint: "URL или настройки сети изменились. Повторите проверку.",
            .websiteDNSTime: "DNS",
            .websiteTotalTime: "Всего",
            .websiteWaiting: "Ожидание проверки",
            .websiteCopyResults: "Скопировать результаты",
            .profileDownloadNotConfiguration: "Сервер не вернул конфигурацию YAML Clash/Mihomo. Скопируйте ссылку подписки в формате Clash/Mihomo у провайдера.",
            .profileTrafficSnapshot: "Данные YAML",
            .profileTrafficSnapshotHelpFormat: "Данные YAML от %@. Импортируйте URL подписки для обновления квоты.",
            .profileTrafficLocal: "Локальный YAML",
            .profileTrafficLocalHelp: "В этом YAML нет данных о квоте. Импортируйте URL подписки для получения данных провайдера.",
            .profileTrafficNotReported: "Квота не указана",
            .profileTrafficNotReportedHelp: "Сервер подписки не предоставил данные о квоте.",
            .profileTrafficRefreshFailed: "Не удалось обновить; показаны последние сохранённые данные.",
            .profileTrafficLeftGBFormat: "Осталось %@ GB",
            .profileTrafficLeftPercentFormat: "Осталось %@",
            .profileTrafficUnavailable: "Нет данных о трафике",
            .profileTrafficUpdatedFormat: "Данные обновлены %@",
            .importFromFile: "Импорт из файла",
            .importFileHint: "Выберите или перетащите файл YAML",
            .importFromURL: "Импорт по URL",
            .importURLHint: "Вставьте ссылку на конфигурацию Mihomo YAML.",
            .profileURL: "URL конфигурации",
            .downloadAndImport: "Скачать и импортировать",
            .importingProfile: "Импорт…",
            .invalidProfileURL: "Введите корректный URL http:// или https://.",
            .profileDownloadHTTPErrorFormat: "Не удалось скачать (HTTP %d).",
            .profileDownloadInvalidResponse: "Сервер не вернул корректный ответ HTTP.",
            .profileDownloadEmpty: "Скачанная конфигурация пуста.",
            .glassAppearance: "Стекло и размытие",
            .blurStrength: "Сила размытия",
            .glassBlurHint: "Чем выше значение, тем сильнее матовость фона и карточек. Текст и элементы управления остаются чёткими.",
            .glassAccessibilityHint: "Настройка macOS «Уменьшить прозрачность» имеет приоритет.",
            .resetGlassAppearance: "Сбросить",

            .menuQuickAccess: "Быстрый доступ",
            .menuNodes: "Узлы",
            .noMatchingNodes: "Нет подходящих узлов",
            .menuSelectedNode: "Выбранный узел",
            .updating: "Обновление…",
            .settings: "Настройки", .settingsSubtitle: "Настройте Nexora и просмотрите сведения о приложении.",
            .appearance: "Оформление", .colorScheme: "Цветовая схема", .accentColor: "Акцентный цвет", .reduceMotion: "Уменьшение движения", .system: "Системная",
            .light: "Светлая", .dark: "Тёмная", .language: "Язык", .systemDefault: "Системный язык",
            .latencyTesting: "Тест задержки", .latencyTestURL: "URL теста",
            .latencyTestTimeout: "Тайм-аут",
            .about: "О программе", .version: "Версия", .engine: "Ядро", .legalNotice: "Правовая информация",
            .permittedUse: "Разрешённое использование", .yourResponsibility: "Ваша ответственность",
            .noWarranty: "Отказ от гарантий и ограничение ответственности",
            .thirdPartyServices: "Сторонние сервисы", .indemnification: "Возмещение убытков",
            .disclaimerPurpose: "Nexora предоставляется исключительно для законных образовательных, академических, исследовательских и связанных с совместимостью и безопасностью целей.",
            .disclaimerResponsibility: "Вы несёте исключительную ответственность за получение необходимых разрешений и соблюдение применимых законов, правил, лицензий, сетевых политик и условий третьих лиц. Запрещено использовать программу для несанкционированного доступа, вмешательства в работу сервисов, незаконного обхода ограничений, нарушения прав или содействия незаконной деятельности.",
            .disclaimerLiability: "В максимально допустимой законом степени программа предоставляется «как есть» и «по мере доступности» без каких-либо гарантий. Разработчик и участники не несут ответственности за прямые, косвенные, случайные, специальные, штрафные или последующие убытки, связанные с программой или её использованием.",
            .disclaimerThirdParties: "Mihomo, сетевые и подписочные провайдеры, веб-сайты и другие сторонние компоненты или сервисы независимы от Nexora. Их доступность, безопасность, содержимое, поведение и условия не контролируются разработчиком.",
            .disclaimerIndemnity: "В максимально допустимой законом степени вы соглашаетесь защищать разработчика и участников и возмещать им претензии, ущерб, штрафы, обязательства, расходы и разумные юридические издержки, возникшие из-за использования, неправильного использования, распространения, настройки или нарушения закона либо прав третьих лиц.",
            .update: "Обновить",
            .checkForUpdates: "Проверить обновления",
            .checkingForUpdates: "Проверка обновлений…",
            .updateAvailableTitle: "Доступно обновление",
            .updateAvailableMessage: "Доступна новая официальная версия Nexora.\n\nТекущая версия: %@\nПоследняя версия: %@\n\nНажмите «Обновить автоматически через Sparkle», чтобы загрузить и установить это обновление.",
            .updateWithSparkle: "Обновить автоматически через Sparkle",
            .updateLater: "Позже",
            .upToDateTitle: "Установлена актуальная версия",
            .upToDateMessage: "Используемая вами версия Nexora %@ является самой новой из опубликованных. Обновление не требуется.",
            .updateCheckFailedTitle: "Не удалось проверить обновления",
            .updateCheckFailedMessage: "В данный момент не удаётся получить сведения об обновлениях. Проверьте сетевое подключение и повторите попытку.\n\nПодробности: %@",
            .updateCheckUnavailable: "Проверка обновлений сейчас недоступна. Повторите попытку позже.",
            .dashboard: "Панель", .diagnostics: "Диагностика",
            .proxies: "Прокси", .routing: "Маршрутизация",
            .profiles: "Профили", .connections: "Соединения",
            .coreStatus: "Состояние ядра",
            .quickEdit: "Быстрое редактирование", .cancel: "Отмена", .confirm: "Подтвердить",
            .restartCore: "Перезапустить ядро", .startCore: "Запустить ядро",
            .renameProfile: "Переименовать профиль", .profileName: "Имя профиля", .rename: "Переименовать",
            .systemProxy: "Системный прокси", .networkSpeed: "Скорость сети",
            .networkDetection: "Определение сети", .outboundMode: "Режим выхода",
            .networkDoctor: "Диагностика сети", .runNetworkDoctor: "Запустить диагностику сети",
            .diagnosticSnapshot: "Снимок диагностики",
            .diagnosticExplanationTitle: "Объяснение диагностики",
            .diagnosticExplanationPlaceholder: "Запустите диагностику сети, чтобы понять результаты проверок и дальнейшие действия.",
            .diagnosticExplanationRules: "Правила диагностики",
            .diagnosticExplanationModel: "Локальная модель",
            .diagnosticExplanationEvidence: "Результаты проверок",
            .diagnosticExplanationNextSteps: "Следующие шаги",
            .diagnosticExplanationAIAction: "Объяснить с локальным ИИ",
            .diagnosticExplanationGenerating: "Подготовка локального объяснения…",
            .diagnosticExplanationSnapshotHint: "Объяснение основано на этом снимке. После изменения сети повторите диагностику.",
            .diagnosticExplanationPrivacyHint: "Локальный ИИ обрабатывает только обезличенные результаты. Конфигурации и журналы не отправляются.",
            .diagnosticExplanationUnsupportedSystem: "Для локального ИИ требуется macOS 26 или новее. Объяснение по правилам остаётся доступным.",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence выключена. Включите её в Системных настройках для локального ИИ; правила диагностики остаются доступны.",
            .diagnosticExplanationModelNotReady: "Локальная модель ещё не готова. Повторите после завершения подготовки macOS.",
            .diagnosticExplanationDeviceIneligible: "Это устройство сейчас не может использовать локальную модель Apple Intelligence. Правила диагностики остаются доступны.",
            .diagnosticExplanationModelUnavailable: "Локальная модель недоступна. Правила диагностики остаются доступны.",
            .diagnosticExplanationFallback: "Локальная модель не завершила работу. Показано объяснение по правилам.",
            .diagnosticExplanationStale: "Устаревший снимок",
            .diagnosticExplanationStaleHint: "Состояние сети изменилось. Это объяснение предыдущей диагностики; запустите новую.",
            .networkDiagnosisHint: "Запустите диагностику маршрута, DNS, портов и внешних проверок.",
            .diagnosticReadyHeadline: "Готово к диагностике", .diagnosticBlockingHeadline: "Обнаружена блокировка",
            .diagnosticAttentionHeadline: "Маршрут требует внимания", .diagnosticCleanHeadline: "Маршрут работает нормально",
            .diagnosticReadyDetailFormat: "Диагностика сети · %d",
            .diagnosticResultDetailFormat: "%@ · проверок: %d",
            .diagnosticChecks: "Проверки", .diagnosticExit: "Выход",
            .portRadar: "Радар портов", .findings: "Выводы",
            .dnsProbe: "Проверка DNS", .endpointProbe: "Проверка конечных точек", .diagnose: "Диагностика",
            .copyReport: "Копировать отчёт", .suggestedAction: "Рекомендация",
            .detectingEgress: "Определение выхода", .directEgress: "Прямой выход",
            .proxyEgress: "Выход через прокси", .systemTunnelEgress: "Системный туннель",
            .unavailableEgress: "Выход недоступен",
            .trafficUsage: "Трафик", .intranetIP: "Локальный IP", .options: "Параметры",
            .rule: "Правила", .global: "Глобальный", .direct: "Напрямую", .upload: "Отправка", .download: "Загрузка",
            .search: "Поиск", .closeAll: "Закрыть все", .refresh: "Обновить",
            .noConnections: "Нет соединений", .host: "Хост", .chain: "Цепочка",
            .closeConnection: "Закрыть соединение", .ready: "Готово", .errors: "Ошибки",
            .warnings: "Предупреждения",
            .stopped: "Остановлено", .connected: "Подключено",
            .coreRunning: "Ядро работает", .nodes: "узлов", .allNodes: "Все",
            .selectedOnly: "Выбрано", .untested: "Не проверено", .slowNodes: "Медленные",
            .noProxyNodes: "Нет доступных прокси-узлов",
            .validateAll: "Проверить все", .openManagedFolder: "Открыть папку профилей",
            .importYAML: "Импорт YAML", .importConfiguration: "Импортировать конфигурацию",
            .noMatchingProfiles: "Нет подходящих профилей", .allProfiles: "Все",
            .deleteProfile: "Удалить профиль",
            .managedYAML: "Управляемый YAML", .running: "Работает", .current: "Текущий",
            .managed: "Управляемый", .selected: "Выбран", .use: "Использовать",
            .validate: "Проверить", .revealInFinder: "Показать в Finder", .delete: "Удалить",
            .notValidated: "Не проверено", .checking: "Проверка", .valid: "Готово",
            .invalid: "Требует исправления",
            .delayTest: "Тест задержки", .automatic: "Автоматически",
            .collapse: "Свернуть", .expand: "Развернуть", .addRule: "Добавить правило",
            .saving: "Сохранение", .domainRouting: "Маршрутизация доменов",
            .deleteRule: "Удалить правило", .noMatchingRoutingRules: "Нет подходящих правил",
            .addDomainHint: "Добавьте домен и выберите VPN или прямой маршрут",
            .start: "Запустить", .pause: "Пауза",
            .tab: "Вкладки", .list: "Список", .selector: "Селектор", .proxy: "Прокси",
            .urlTest: "URL-тест", .fallback: "Резерв", .loadBalance: "Балансировка",
            .profileStorageFormat: "Профиль: %@ · хранится отдельно от исходного YAML",
            .selectProfileBeforeRules: "Перед добавлением правил выберите управляемый профиль",
            .ruleCountSingular: "%d правило", .ruleCountPlural: "%d правил",
            .routingExplanation: "Правила VPN используют основную выбираемую прокси-группу профиля. Прямые правила обходят прокси-цепочку Mihomo.",
            .poweredByMihomo: "На базе Mihomo",
            .ok: "ОК", .renameMenuBarNote: "Новое имя также отображается в панели строки меню.",
            .restartActiveExplanation: "Mihomo и активный VPN-сеанс будут перезапущены, после чего восстановится текущий режим выхода.",
            .restartControllerExplanation: "Сеанс контроллера Mihomo будет перезапущен без включения системного VPN.",
            .startControllerExplanation: "Mihomo остановлен. Подтвердите запуск ядра только в режиме контроллера.",
            .deleteProfileFormat: "Удалить «%@»?", .profile: "Профиль",
            .deleteProfileExplanation: "Управляемая копия YAML и сохранённые правила маршрутизации будут удалены.",
        ],
        .spanish: [
            .clearSearch: "Borrar búsqueda",
            .websiteComparisonTitle: "Comparación de conexión web",
            .websiteComparisonHint: "Introduce una URL para comparar el acceso directo con la ruta actual de Nexora.",
            .websiteURL: "URL del sitio",
            .websiteURLPlaceholder: "example.com o https://example.com/path",
            .websiteCompare: "Comprobar sitio",
            .websiteDirectRoute: "Directo",
            .websiteNexoraRoute: "Vía Nexora",
            .websiteDirectHint: "Omite la configuración del proxy del sistema.",
            .websiteNexoraHint: "Sigue el modo y las reglas actuales; la ruta también puede ser directa.",
            .websiteTunnelWarning: "Hay un túnel del sistema activo: ambas solicitudes pueden usarlo. Directo no equivale a desactivar la VPN.",
            .websiteInvalidURL: "Introduce una URL HTTP(S) válida sin usuario ni contraseña incluidos.",
            .websiteProxyInactive: "No hay un proxy Nexora en ejecución.",
            .websiteResponseReceived: "El servidor ha respondido.",
            .websiteHTTPRestricted: "El servidor ha respondido; revisa el inicio de sesión, los permisos o el estado del sitio.",
            .websiteDNSFailure: "Falló la resolución DNS.",
            .websiteConnectionFailure: "No se pudo establecer la conexión.",
            .websiteTLSFailure: "Falló el certificado HTTPS o la negociación segura.",
            .websiteTimeout: "Se agotó el tiempo de espera.",
            .websiteRequestFailure: "La solicitud no se completó. Inténtalo de nuevo.",
            .websiteProxyAuthentication: "El proxy requiere autenticación.",
            .websiteCancelled: "Cancelado. Puedes repetir la comparación.",
            .websiteStaleHint: "La URL o la configuración de red ha cambiado. Repite la comparación.",
            .websiteDNSTime: "DNS",
            .websiteTotalTime: "Total",
            .websiteWaiting: "Esperando prueba",
            .websiteCopyResults: "Copiar resultados",
            .profileDownloadNotConfiguration: "El servidor no ha devuelto una configuración YAML de Clash/Mihomo. Copie el enlace de suscripción de Clash/Mihomo de su proveedor.",
            .profileTrafficSnapshot: "Datos del YAML",
            .profileTrafficSnapshotHelpFormat: "Datos del YAML del %@. Importe una URL de suscripción para actualizar la cuota.",
            .profileTrafficLocal: "YAML local",
            .profileTrafficLocalHelp: "Este YAML no contiene la cuota. Importe la URL de suscripción para obtener datos del proveedor.",
            .profileTrafficNotReported: "Cuota no indicada",
            .profileTrafficNotReportedHelp: "El servidor de suscripción no ha proporcionado la cuota.",
            .profileTrafficRefreshFailed: "Error al actualizar; se conservan los últimos datos.",
            .profileTrafficLeftGBFormat: "%@ GB restantes",
            .profileTrafficLeftPercentFormat: "%@ restante",
            .profileTrafficUnavailable: "Tráfico no disponible",
            .profileTrafficUpdatedFormat: "Tráfico actualizado %@",
            .importFromFile: "Importar desde un archivo",
            .importFileHint: "Selecciona o arrastra un archivo YAML",
            .importFromURL: "Importar desde una URL",
            .importURLHint: "Pega un enlace a una configuración YAML de Mihomo.",
            .profileURL: "URL de la configuración",
            .downloadAndImport: "Descargar e importar",
            .importingProfile: "Importando…",
            .invalidProfileURL: "Introduce una URL http:// o https:// válida.",
            .profileDownloadHTTPErrorFormat: "Error al descargar (HTTP %d).",
            .profileDownloadInvalidResponse: "El servidor no devolvió una respuesta HTTP válida.",
            .profileDownloadEmpty: "La configuración descargada está vacía.",
            .glassAppearance: "Cristal y desenfoque",
            .blurStrength: "Intensidad del desenfoque",
            .glassBlurHint: "Los valores altos refuerzan el efecto esmerilado del fondo y las tarjetas. El texto y los controles siguen nítidos.",
            .glassAccessibilityHint: "Reducir transparencia de macOS tiene prioridad.",
            .resetGlassAppearance: "Restablecer",

            .menuQuickAccess: "Acceso rápido",
            .menuNodes: "Nodos",
            .noMatchingNodes: "No hay nodos coincidentes",
            .menuSelectedNode: "Nodo seleccionado",
            .updating: "Actualizando…",
            .settings: "Ajustes", .settingsSubtitle: "Personaliza Nexora y consulta la información de la aplicación.",
            .appearance: "Apariencia", .colorScheme: "Esquema de color", .accentColor: "Color de acento", .reduceMotion: "Reducir movimiento", .system: "Sistema",
            .light: "Claro", .dark: "Oscuro", .language: "Idioma", .systemDefault: "Idioma del sistema",
            .latencyTesting: "Prueba de latencia", .latencyTestURL: "URL de prueba",
            .latencyTestTimeout: "Tiempo de espera",
            .about: "Acerca de", .version: "Versión", .engine: "Motor", .legalNotice: "Aviso legal",
            .permittedUse: "Uso permitido", .yourResponsibility: "Tu responsabilidad",
            .noWarranty: "Sin garantía y limitación de responsabilidad",
            .thirdPartyServices: "Servicios de terceros", .indemnification: "Indemnización",
            .disclaimerPurpose: "Nexora se proporciona únicamente para fines legales educativos, académicos, de interoperabilidad y de investigación de seguridad.",
            .disclaimerResponsibility: "Eres el único responsable de obtener las autorizaciones necesarias y cumplir las leyes, reglamentos, licencias, políticas de red y condiciones de terceros aplicables. No debes utilizar el software para acceso no autorizado, interferencia con servicios, elusión ilegal, infracción de derechos o actividades ilícitas.",
            .disclaimerLiability: "En la máxima medida permitida por la ley, el software se proporciona «tal cual» y «según disponibilidad», sin garantías de ningún tipo. El desarrollador y los colaboradores no serán responsables de pérdidas directas, indirectas, incidentales, especiales, punitivas o consecuentes relacionadas con el software o su uso.",
            .disclaimerThirdParties: "Mihomo, los proveedores de red o suscripción, los sitios web y otros componentes o servicios de terceros son independientes de Nexora. Su disponibilidad, seguridad, contenido, conducta y condiciones quedan fuera del control del desarrollador.",
            .disclaimerIndemnity: "En la máxima medida permitida por la ley, aceptas defender, indemnizar y mantener indemnes al desarrollador y a los colaboradores frente a reclamaciones, daños, sanciones, responsabilidades, costes y honorarios legales razonables derivados de tu uso, uso indebido, distribución, configuración o infracción de la ley o de derechos de terceros.",
            .update: "Actualizar",
            .checkForUpdates: "Buscar actualizaciones",
            .checkingForUpdates: "Buscando actualizaciones…",
            .updateAvailableTitle: "Actualización disponible",
            .updateAvailableMessage: "Hay una nueva versión oficial de Nexora disponible.\n\nVersión actual: %@\nÚltima versión: %@\n\nHaz clic en «Actualizar automáticamente con Sparkle» para descargar e instalar esta versión.",
            .updateWithSparkle: "Actualizar automáticamente con Sparkle",
            .updateLater: "Más tarde",
            .upToDateTitle: "La aplicación está actualizada",
            .upToDateMessage: "La versión de Nexora %@ que estás utilizando es la última publicada actualmente. No es necesario actualizar.",
            .updateCheckFailedTitle: "Error al buscar actualizaciones",
            .updateCheckFailedMessage: "No se pudo obtener la información de actualización en este momento. Comprueba la conexión de red e inténtalo de nuevo.\n\nDetalles: %@",
            .updateCheckUnavailable: "La comprobación de actualizaciones no está disponible en este momento. Inténtalo de nuevo más tarde.",
            .dashboard: "Panel", .diagnostics: "Diagnóstico",
            .proxies: "Proxies", .routing: "Enrutamiento",
            .profiles: "Perfiles", .connections: "Conexiones",
            .coreStatus: "Estado del núcleo",
            .quickEdit: "Edición rápida", .cancel: "Cancelar", .confirm: "Confirmar",
            .restartCore: "Reiniciar núcleo", .startCore: "Iniciar núcleo",
            .renameProfile: "Renombrar perfil", .profileName: "Nombre del perfil", .rename: "Renombrar",
            .systemProxy: "Proxy del sistema", .networkSpeed: "Velocidad de red",
            .networkDetection: "Detección de red", .outboundMode: "Modo de salida",
            .networkDoctor: "Diagnóstico de red", .runNetworkDoctor: "Ejecutar diagnóstico de red",
            .diagnosticSnapshot: "Instantánea del diagnóstico",
            .diagnosticExplanationTitle: "Explicación del diagnóstico",
            .diagnosticExplanationPlaceholder: "Ejecuta un diagnóstico de red para entender las comprobaciones y qué hacer después.",
            .diagnosticExplanationRules: "Reglas de diagnóstico",
            .diagnosticExplanationModel: "Modelo local",
            .diagnosticExplanationEvidence: "Evidencia",
            .diagnosticExplanationNextSteps: "Próximos pasos",
            .diagnosticExplanationAIAction: "Explicar con IA local",
            .diagnosticExplanationGenerating: "Preparando explicación local…",
            .diagnosticExplanationSnapshotHint: "Esta explicación se basa en esta instantánea. Repite el diagnóstico si cambia la red.",
            .diagnosticExplanationPrivacyHint: "La IA local solo procesa resultados anonimizados. No se envían configuraciones ni registros.",
            .diagnosticExplanationUnsupportedSystem: "La IA local requiere macOS 26 o posterior. Las reglas de diagnóstico siguen disponibles.",
            .diagnosticExplanationIntelligenceDisabled: "Apple Intelligence está desactivada. Actívala en Ajustes del Sistema para usar la IA local; las reglas siguen disponibles.",
            .diagnosticExplanationModelNotReady: "El modelo local no está listo. Inténtalo cuando macOS termine de prepararlo.",
            .diagnosticExplanationDeviceIneligible: "Este dispositivo no puede usar el modelo local de Apple Intelligence actualmente. Las reglas siguen disponibles.",
            .diagnosticExplanationModelUnavailable: "El modelo local no está disponible. Las reglas de diagnóstico siguen disponibles.",
            .diagnosticExplanationFallback: "El modelo local no terminó. Se muestran las reglas de diagnóstico.",
            .diagnosticExplanationStale: "Instantánea desactualizada",
            .diagnosticExplanationStaleHint: "El estado de la red ha cambiado. Esta explicación corresponde al diagnóstico anterior; ejecuta uno nuevo.",
            .networkDiagnosisHint: "Ejecuta un diagnóstico para revisar ruta, DNS, puertos y pruebas externas.",
            .diagnosticReadyHeadline: "Listo para el diagnóstico", .diagnosticBlockingHeadline: "Bloqueo detectado",
            .diagnosticAttentionHeadline: "La ruta requiere atención", .diagnosticCleanHeadline: "La ruta funciona correctamente",
            .diagnosticReadyDetailFormat: "Diagnóstico de red · %d",
            .diagnosticResultDetailFormat: "%@ · %d comprobaciones",
            .diagnosticChecks: "Comprobaciones", .diagnosticExit: "Salida",
            .portRadar: "Radar de puertos", .findings: "Hallazgos",
            .dnsProbe: "Prueba DNS", .endpointProbe: "Prueba de endpoints", .diagnose: "Diagnosticar",
            .copyReport: "Copiar informe", .suggestedAction: "Acción sugerida",
            .detectingEgress: "Detectando salida", .directEgress: "Salida directa",
            .proxyEgress: "Salida proxy", .systemTunnelEgress: "Túnel del sistema",
            .unavailableEgress: "Salida no disponible",
            .trafficUsage: "Uso de datos", .intranetIP: "IP local", .options: "Opciones",
            .rule: "Reglas", .global: "Global", .direct: "Directo", .upload: "Subida", .download: "Descarga",
            .search: "Buscar", .closeAll: "Cerrar todo", .refresh: "Actualizar",
            .noConnections: "Sin conexiones", .host: "Host", .chain: "Cadena",
            .closeConnection: "Cerrar conexión", .ready: "Listo", .errors: "Errores",
            .warnings: "Alertas", .stopped: "Detenido",
            .connected: "Conectado",
            .coreRunning: "Núcleo activo", .nodes: "nodos", .allNodes: "Todos",
            .selectedOnly: "Seleccionados", .untested: "Sin probar", .slowNodes: "Lentos",
            .noProxyNodes: "No hay nodos proxy disponibles",
            .validateAll: "Validar todo", .openManagedFolder: "Abrir carpeta gestionada",
            .importYAML: "Importar YAML", .importConfiguration: "Importar configuración",
            .noMatchingProfiles: "No hay perfiles coincidentes", .allProfiles: "Todos",
            .deleteProfile: "Eliminar perfil",
            .managedYAML: "YAML gestionado", .running: "En ejecución", .current: "Actual",
            .managed: "Gestionado", .selected: "Seleccionado", .use: "Usar",
            .validate: "Validar", .revealInFinder: "Mostrar en Finder", .delete: "Eliminar",
            .notValidated: "Sin comprobar", .checking: "Comprobando", .valid: "Válido",
            .invalid: "Requiere corrección",
            .delayTest: "Prueba de latencia", .automatic: "Automático",
            .collapse: "Contraer", .expand: "Expandir", .addRule: "Añadir regla",
            .saving: "Guardando", .domainRouting: "Enrutamiento de dominios",
            .deleteRule: "Eliminar regla", .noMatchingRoutingRules: "No hay reglas coincidentes",
            .addDomainHint: "Añade un dominio y elige VPN o conexión directa",
            .start: "Iniciar", .pause: "Pausar",
            .tab: "Pestañas", .list: "Lista", .selector: "Selector", .proxy: "Proxy",
            .urlTest: "Prueba URL", .fallback: "Respaldo", .loadBalance: "Balanceo de carga",
            .profileStorageFormat: "Perfil: %@ · guardado por separado de su YAML",
            .selectProfileBeforeRules: "Selecciona un perfil gestionado antes de añadir reglas",
            .ruleCountSingular: "%d regla", .ruleCountPlural: "%d reglas",
            .routingExplanation: "Las reglas VPN usan el grupo proxy seleccionable principal del perfil. Las reglas directas omiten la cadena proxy de Mihomo.",
            .poweredByMihomo: "Con tecnología de Mihomo",
            .ok: "Aceptar", .renameMenuBarNote: "El nombre nuevo también aparecerá en el panel de la barra de menús.",
            .restartActiveExplanation: "Mihomo y la sesión VPN activa se reiniciarán y después se restaurará el modo de salida actual.",
            .restartControllerExplanation: "La sesión de controlador de Mihomo se reiniciará sin activar la VPN del sistema.",
            .startControllerExplanation: "Mihomo está detenido. Confirma para iniciar el núcleo solo en modo controlador.",
            .deleteProfileFormat: "¿Eliminar «%@»?", .profile: "Perfil",
            .deleteProfileExplanation: "Se eliminarán la copia YAML gestionada y sus reglas de enrutamiento guardadas.",
        ],
        .portuguese: [
            .clearSearch: "Limpar pesquisa",
            .websiteComparisonTitle: "Comparação de ligação web",
            .websiteComparisonHint: "Introduza um URL para comparar o acesso direto com a rota atual do Nexora.",
            .websiteURL: "URL do site",
            .websiteURLPlaceholder: "example.com ou https://example.com/path",
            .websiteCompare: "Verificar site",
            .websiteDirectRoute: "Direto",
            .websiteNexoraRoute: "Via Nexora",
            .websiteDirectHint: "Ignora as definições de proxy do sistema.",
            .websiteNexoraHint: "Segue o modo e as regras atuais; a rota também pode ser direta.",
            .websiteTunnelWarning: "Existe um túnel de sistema ativo: ambos os pedidos podem usá-lo. Direto não equivale a desligar a VPN.",
            .websiteInvalidURL: "Introduza um URL HTTP(S) válido sem nome de utilizador nem palavra-passe incluídos.",
            .websiteProxyInactive: "Não existe um proxy Nexora em execução.",
            .websiteResponseReceived: "O servidor respondeu.",
            .websiteHTTPRestricted: "O servidor respondeu; verifique o início de sessão, as permissões ou o estado do site.",
            .websiteDNSFailure: "Falha na resolução DNS.",
            .websiteConnectionFailure: "Não foi possível estabelecer a ligação.",
            .websiteTLSFailure: "Falha no certificado HTTPS ou na negociação segura.",
            .websiteTimeout: "O pedido excedeu o tempo limite.",
            .websiteRequestFailure: "O pedido não foi concluído. Tente novamente.",
            .websiteProxyAuthentication: "O proxy requer autenticação.",
            .websiteCancelled: "Cancelado. Pode repetir a comparação.",
            .websiteStaleHint: "O URL ou as definições de rede mudaram. Repita a comparação.",
            .websiteDNSTime: "DNS",
            .websiteTotalTime: "Total",
            .websiteWaiting: "A aguardar teste",
            .websiteCopyResults: "Copiar resultados",
            .profileDownloadNotConfiguration: "O servidor não devolveu uma configuração YAML Clash/Mihomo. Copie o link de subscrição Clash/Mihomo do seu fornecedor.",
            .profileTrafficSnapshot: "Dados do YAML",
            .profileTrafficSnapshotHelpFormat: "Dados do YAML de %@. Importe um URL de subscrição para atualizar a quota.",
            .profileTrafficLocal: "YAML local",
            .profileTrafficLocalHelp: "Este YAML não contém a quota. Importe o URL de subscrição para obter os dados do fornecedor.",
            .profileTrafficNotReported: "Quota não fornecida",
            .profileTrafficNotReportedHelp: "O servidor de subscrição não forneceu a quota.",
            .profileTrafficRefreshFailed: "Falha na atualização; os últimos dados foram mantidos.",
            .profileTrafficLeftGBFormat: "%@ GB restantes",
            .profileTrafficLeftPercentFormat: "%@ restante",
            .profileTrafficUnavailable: "Tráfego indisponível",
            .profileTrafficUpdatedFormat: "Tráfego atualizado em %@",
            .importFromFile: "Importar de um ficheiro",
            .importFileHint: "Escolha ou arraste um ficheiro YAML",
            .importFromURL: "Importar de um URL",
            .importURLHint: "Cole um link para uma configuração YAML do Mihomo.",
            .profileURL: "URL da configuração",
            .downloadAndImport: "Descarregar e importar",
            .importingProfile: "A importar…",
            .invalidProfileURL: "Introduza um URL http:// ou https:// válido.",
            .profileDownloadHTTPErrorFormat: "Falha ao descarregar (HTTP %d).",
            .profileDownloadInvalidResponse: "O servidor não devolveu uma resposta HTTP válida.",
            .profileDownloadEmpty: "A configuração descarregada está vazia.",
            .glassAppearance: "Vidro e desfoque",
            .blurStrength: "Intensidade do desfoque",
            .glassBlurHint: "Valores maiores reforçam o vidro fosco do fundo e dos cartões. O texto e os controlos continuam nítidos.",
            .glassAccessibilityHint: "Reduzir transparência do macOS tem prioridade.",
            .resetGlassAppearance: "Repor",

            .menuQuickAccess: "Acesso rápido",
            .menuNodes: "Nós",
            .noMatchingNodes: "Nenhum nó correspondente",
            .menuSelectedNode: "Nó selecionado",
            .updating: "Atualizando…",
            .settings: "Definições", .settingsSubtitle: "Personalize o Nexora e consulte as informações da aplicação.",
            .appearance: "Aparência", .colorScheme: "Esquema de cores", .accentColor: "Cor de destaque", .reduceMotion: "Reduzir movimento", .system: "Sistema",
            .light: "Claro", .dark: "Escuro", .language: "Idioma", .systemDefault: "Idioma do sistema",
            .latencyTesting: "Teste de latência", .latencyTestURL: "URL de teste",
            .latencyTestTimeout: "Tempo limite",
            .about: "Acerca de", .version: "Versão", .engine: "Motor", .legalNotice: "Aviso legal",
            .permittedUse: "Utilização permitida", .yourResponsibility: "A sua responsabilidade",
            .noWarranty: "Sem garantia e limitação de responsabilidade",
            .thirdPartyServices: "Serviços de terceiros", .indemnification: "Indemnização",
            .disclaimerPurpose: "O Nexora é fornecido exclusivamente para fins legais de educação, investigação académica, interoperabilidade e segurança.",
            .disclaimerResponsibility: "É o único responsável por obter todas as autorizações necessárias e cumprir as leis, regulamentos, licenças, políticas de rede e termos de terceiros aplicáveis. Não deve utilizar o software para acesso não autorizado, interferência em serviços, contorno ilegal, violação de direitos ou atividades ilícitas.",
            .disclaimerLiability: "Na máxima medida permitida por lei, o software é fornecido «tal como está» e «conforme disponível», sem garantias de qualquer tipo. O programador e os colaboradores não são responsáveis por perdas diretas, indiretas, incidentais, especiais, punitivas ou consequenciais relacionadas com o software ou a sua utilização.",
            .disclaimerThirdParties: "Mihomo, fornecedores de rede ou subscrição, sites e outros componentes ou serviços de terceiros são independentes do Nexora. A sua disponibilidade, segurança, conteúdo, conduta e termos estão fora do controlo do programador.",
            .disclaimerIndemnity: "Na máxima medida permitida por lei, concorda em defender, indemnizar e isentar o programador e os colaboradores de reclamações, danos, penalizações, responsabilidades, custos e honorários jurídicos razoáveis decorrentes da sua utilização, utilização indevida, distribuição, configuração ou violação da lei ou de direitos de terceiros.",
            .update: "Atualizar",
            .checkForUpdates: "Procurar atualizações",
            .checkingForUpdates: "A procurar atualizações…",
            .updateAvailableTitle: "Atualização disponível",
            .updateAvailableMessage: "Está disponível uma nova versão oficial do Nexora.\n\nVersão atual: %@\nVersão mais recente: %@\n\nClique em «Atualizar automaticamente via Sparkle» para descarregar e instalar esta versão.",
            .updateWithSparkle: "Atualizar automaticamente via Sparkle",
            .updateLater: "Mais tarde",
            .upToDateTitle: "Está atualizado",
            .upToDateMessage: "O Nexora %@ que está a utilizar já é a versão mais recente disponível. Não é necessária nenhuma atualização.",
            .updateCheckFailedTitle: "Falha ao procurar atualizações",
            .updateCheckFailedMessage: "Não foi possível obter informações de atualização neste momento. Verifique a ligação à rede e tente novamente.\n\nDetalhes: %@",
            .updateCheckUnavailable: "A verificação de atualizações não está disponível neste momento. Tente novamente mais tarde.",
            .dashboard: "Painel", .diagnostics: "Diagnóstico",
            .proxies: "Proxies", .routing: "Encaminhamento",
            .profiles: "Perfis", .connections: "Ligações",
            .coreStatus: "Estado do núcleo",
            .quickEdit: "Edição rápida", .cancel: "Cancelar", .confirm: "Confirmar",
            .restartCore: "Reiniciar núcleo", .startCore: "Iniciar núcleo",
            .renameProfile: "Mudar nome do perfil", .profileName: "Nome do perfil", .rename: "Mudar nome",
            .systemProxy: "Proxy do sistema", .networkSpeed: "Velocidade da rede",
            .networkDetection: "Deteção de rede", .outboundMode: "Modo de saída",
            .networkDoctor: "Diagnóstico de rede", .runNetworkDoctor: "Executar diagnóstico de rede",
            .diagnosticSnapshot: "Instantâneo do diagnóstico",
            .diagnosticExplanationTitle: "Explicação do diagnóstico",
            .diagnosticExplanationPlaceholder: "Execute um diagnóstico de rede para compreender as verificações e os próximos passos.",
            .diagnosticExplanationRules: "Regras de diagnóstico",
            .diagnosticExplanationModel: "Modelo local",
            .diagnosticExplanationEvidence: "Evidências",
            .diagnosticExplanationNextSteps: "Próximos passos",
            .diagnosticExplanationAIAction: "Explicar com IA local",
            .diagnosticExplanationGenerating: "A preparar explicação local…",
            .diagnosticExplanationSnapshotHint: "A explicação baseia-se neste instantâneo. Repita o diagnóstico se a rede mudar.",
            .diagnosticExplanationPrivacyHint: "A IA local processa apenas resultados anonimizados. As configurações e os registos não são enviados.",
            .diagnosticExplanationUnsupportedSystem: "A IA local requer macOS 26 ou posterior. As regras de diagnóstico continuam disponíveis.",
            .diagnosticExplanationIntelligenceDisabled: "A Apple Intelligence está desativada. Ative-a nas Definições do Sistema para usar a IA local; as regras continuam disponíveis.",
            .diagnosticExplanationModelNotReady: "O modelo local ainda não está pronto. Tente novamente quando o macOS concluir a preparação.",
            .diagnosticExplanationDeviceIneligible: "Este dispositivo não pode usar o modelo local da Apple Intelligence neste momento. As regras continuam disponíveis.",
            .diagnosticExplanationModelUnavailable: "O modelo local está indisponível. As regras de diagnóstico continuam disponíveis.",
            .diagnosticExplanationFallback: "O modelo local não concluiu. São apresentadas as regras de diagnóstico.",
            .diagnosticExplanationStale: "Instantâneo desatualizado",
            .diagnosticExplanationStaleHint: "O estado da rede mudou. Esta explicação é do diagnóstico anterior; execute um novo diagnóstico.",
            .networkDiagnosisHint: "Execute um diagnóstico para verificar rota, DNS, portas e sondas externas.",
            .diagnosticReadyHeadline: "Pronto para diagnóstico", .diagnosticBlockingHeadline: "Bloqueio detetado",
            .diagnosticAttentionHeadline: "A rota requer atenção", .diagnosticCleanHeadline: "A rota está normal",
            .diagnosticReadyDetailFormat: "Diagnóstico de rede · %d",
            .diagnosticResultDetailFormat: "%@ · %d verificações",
            .diagnosticChecks: "Verificações", .diagnosticExit: "Saída",
            .portRadar: "Radar de portas", .findings: "Achados",
            .dnsProbe: "Sonda DNS", .endpointProbe: "Sonda de endpoints", .diagnose: "Diagnosticar",
            .copyReport: "Copiar relatório", .suggestedAction: "Ação sugerida",
            .detectingEgress: "A detetar saída", .directEgress: "Saída direta",
            .proxyEgress: "Saída proxy", .systemTunnelEgress: "Túnel do sistema",
            .unavailableEgress: "Saída indisponível",
            .trafficUsage: "Utilização de dados", .intranetIP: "IP local", .options: "Opções",
            .rule: "Regras", .global: "Global", .direct: "Direto", .upload: "Envio", .download: "Receção",
            .search: "Pesquisar", .closeAll: "Fechar tudo", .refresh: "Atualizar",
            .noConnections: "Sem ligações", .host: "Anfitrião", .chain: "Cadeia",
            .closeConnection: "Fechar ligação", .ready: "Pronto", .errors: "Erros",
            .warnings: "Avisos", .stopped: "Parado",
            .connected: "Ligado",
            .coreRunning: "Núcleo ativo", .nodes: "nós", .allNodes: "Todos",
            .selectedOnly: "Selecionados", .untested: "Não testados", .slowNodes: "Lentos",
            .noProxyNodes: "Sem nós proxy disponíveis",
            .validateAll: "Validar tudo", .openManagedFolder: "Abrir pasta gerida",
            .importYAML: "Importar YAML", .importConfiguration: "Importar configuração",
            .noMatchingProfiles: "Sem perfis correspondentes", .allProfiles: "Todos",
            .deleteProfile: "Eliminar perfil",
            .managedYAML: "YAML gerido", .running: "Em execução", .current: "Atual",
            .managed: "Gerido", .selected: "Selecionado", .use: "Usar",
            .validate: "Validar", .revealInFinder: "Mostrar no Finder", .delete: "Eliminar",
            .notValidated: "Não verificado", .checking: "A verificar", .valid: "Válido",
            .invalid: "Requer correção",
            .delayTest: "Teste de latência", .automatic: "Automático",
            .collapse: "Recolher", .expand: "Expandir", .addRule: "Adicionar regra",
            .saving: "A guardar", .domainRouting: "Encaminhamento de domínios",
            .deleteRule: "Eliminar regra", .noMatchingRoutingRules: "Sem regras correspondentes",
            .addDomainHint: "Adicione um domínio e escolha VPN ou ligação direta",
            .start: "Iniciar", .pause: "Pausar",
            .tab: "Separadores", .list: "Lista", .selector: "Seletor", .proxy: "Proxy",
            .urlTest: "Teste URL", .fallback: "Alternativa", .loadBalance: "Balanceamento",
            .profileStorageFormat: "Perfil: %@ · guardado separadamente do respetivo YAML",
            .selectProfileBeforeRules: "Selecione um perfil gerido antes de adicionar regras",
            .ruleCountSingular: "%d regra", .ruleCountPlural: "%d regras",
            .routingExplanation: "As regras VPN utilizam o grupo proxy selecionável principal do perfil. As regras diretas ignoram a cadeia proxy do Mihomo.",
            .poweredByMihomo: "Desenvolvido com Mihomo",
            .ok: "OK", .renameMenuBarNote: "O novo nome também aparece no painel da barra de menus.",
            .restartActiveExplanation: "O Mihomo e a sessão VPN ativa serão reiniciados e o modo de saída atual será restaurado.",
            .restartControllerExplanation: "A sessão de controlador do Mihomo será reiniciada sem ativar a VPN do sistema.",
            .startControllerExplanation: "O Mihomo está parado. Confirme para iniciar o núcleo apenas no modo de controlador.",
            .deleteProfileFormat: "Eliminar «%@»?", .profile: "Perfil",
            .deleteProfileExplanation: "A cópia YAML gerida e as respetivas regras de encaminhamento guardadas serão eliminadas.",
        ],
    ]
}
