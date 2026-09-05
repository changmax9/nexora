import Foundation

public enum AppString: String, CaseIterable, Sendable {
    case settings
    case settingsSubtitle
    case appearance
    case colorScheme
    case accentColor
    case reduceMotion
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
    case runNetworkDoctor
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
    case noMatchingProfiles
    case allProfiles
    case deleteProfile
    case managedYAML
    case running
    case current
    case managed
    case selected
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
            .update: "更新", .dashboard: "仪表盘", .diagnostics: "诊断",
            .proxies: "代理", .routing: "路由",
            .profiles: "配置", .connections: "连接",
            .coreStatus: "核心状态", .quickEdit: "快速编辑",
            .cancel: "取消", .confirm: "确认", .restartCore: "重启核心", .startCore: "启动核心",
            .renameProfile: "重命名配置", .profileName: "配置名称", .rename: "重命名",
            .systemProxy: "系统代理", .networkSpeed: "网络速度",
            .networkDetection: "网络检测", .outboundMode: "出站模式",
            .networkDoctor: "网络诊断", .runNetworkDoctor: "运行网络诊断",
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
            .update: "更新", .dashboard: "儀表板", .diagnostics: "診斷",
            .proxies: "代理", .routing: "路由",
            .profiles: "設定檔", .connections: "連線",
            .coreStatus: "核心狀態", .quickEdit: "快速編輯",
            .cancel: "取消", .confirm: "確認", .restartCore: "重新啟動核心", .startCore: "啟動核心",
            .renameProfile: "重新命名設定檔", .profileName: "設定檔名稱", .rename: "重新命名",
            .systemProxy: "系統代理", .networkSpeed: "網路速度",
            .networkDetection: "網路偵測", .outboundMode: "出站模式",
            .networkDoctor: "網路診斷", .runNetworkDoctor: "執行網路診斷",
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
            .update: "アップデート", .dashboard: "ダッシュボード", .diagnostics: "診断",
            .proxies: "プロキシ",
            .routing: "ルーティング", .profiles: "プロファイル", .connections: "接続",
            .coreStatus: "コア状態", .quickEdit: "クイック編集", .cancel: "キャンセル",
            .confirm: "確認", .restartCore: "コアを再起動", .startCore: "コアを起動",
            .renameProfile: "プロファイル名を変更", .profileName: "プロファイル名", .rename: "名前を変更",
            .systemProxy: "システムプロキシ", .networkSpeed: "ネットワーク速度",
            .networkDetection: "ネットワーク検出", .outboundMode: "送信モード",
            .networkDoctor: "ネットワーク診断", .runNetworkDoctor: "ネットワーク診断を実行",
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
            .update: "Mise à jour", .dashboard: "Tableau de bord", .diagnostics: "Diagnostics",
            .proxies: "Proxy",
            .routing: "Routage", .profiles: "Profils", .connections: "Connexions",
            .coreStatus: "État du moteur",
            .quickEdit: "Modification rapide", .cancel: "Annuler", .confirm: "Confirmer",
            .restartCore: "Redémarrer le moteur", .startCore: "Démarrer le moteur",
            .renameProfile: "Renommer le profil", .profileName: "Nom du profil", .rename: "Renommer",
            .systemProxy: "Proxy système", .networkSpeed: "Vitesse du réseau",
            .networkDetection: "Détection du réseau", .outboundMode: "Mode de sortie",
            .networkDoctor: "Diagnostic réseau", .runNetworkDoctor: "Lancer le diagnostic réseau",
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
            .update: "Обновить", .dashboard: "Панель", .diagnostics: "Диагностика",
            .proxies: "Прокси", .routing: "Маршрутизация",
            .profiles: "Профили", .connections: "Соединения",
            .coreStatus: "Состояние ядра",
            .quickEdit: "Быстрое редактирование", .cancel: "Отмена", .confirm: "Подтвердить",
            .restartCore: "Перезапустить ядро", .startCore: "Запустить ядро",
            .renameProfile: "Переименовать профиль", .profileName: "Имя профиля", .rename: "Переименовать",
            .systemProxy: "Системный прокси", .networkSpeed: "Скорость сети",
            .networkDetection: "Определение сети", .outboundMode: "Режим выхода",
            .networkDoctor: "Диагностика сети", .runNetworkDoctor: "Запустить диагностику сети",
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
            .update: "Actualizar", .dashboard: "Panel", .diagnostics: "Diagnóstico",
            .proxies: "Proxies", .routing: "Enrutamiento",
            .profiles: "Perfiles", .connections: "Conexiones",
            .coreStatus: "Estado del núcleo",
            .quickEdit: "Edición rápida", .cancel: "Cancelar", .confirm: "Confirmar",
            .restartCore: "Reiniciar núcleo", .startCore: "Iniciar núcleo",
            .renameProfile: "Renombrar perfil", .profileName: "Nombre del perfil", .rename: "Renombrar",
            .systemProxy: "Proxy del sistema", .networkSpeed: "Velocidad de red",
            .networkDetection: "Detección de red", .outboundMode: "Modo de salida",
            .networkDoctor: "Diagnóstico de red", .runNetworkDoctor: "Ejecutar diagnóstico de red",
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
            .update: "Atualizar", .dashboard: "Painel", .diagnostics: "Diagnóstico",
            .proxies: "Proxies", .routing: "Encaminhamento",
            .profiles: "Perfis", .connections: "Ligações",
            .coreStatus: "Estado do núcleo",
            .quickEdit: "Edição rápida", .cancel: "Cancelar", .confirm: "Confirmar",
            .restartCore: "Reiniciar núcleo", .startCore: "Iniciar núcleo",
            .renameProfile: "Mudar nome do perfil", .profileName: "Nome do perfil", .rename: "Mudar nome",
            .systemProxy: "Proxy do sistema", .networkSpeed: "Velocidade da rede",
            .networkDetection: "Deteção de rede", .outboundMode: "Modo de saída",
            .networkDoctor: "Diagnóstico de rede", .runNetworkDoctor: "Executar diagnóstico de rede",
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
