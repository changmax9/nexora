import Foundation
import SwiftUI

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case diagnostics
    case proxies
    case routing
    case profiles
    case connections
    case settings

    public var id: String { rawValue }

    public var title: String {
        AppLanguage.english.text(titleKey)
    }

    public var titleKey: AppString {
        switch self {
        case .dashboard: .dashboard
        case .diagnostics: .diagnostics
        case .proxies: .proxies
        case .routing: .routing
        case .profiles: .profiles
        case .connections: .connections
        case .settings: .settings
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .diagnostics: "stethoscope"
        case .proxies: "doc.text.fill"
        case .routing: "point.3.connected.trianglepath.dotted"
        case .profiles: "folder.fill"
        case .connections: "list.bullet.rectangle.fill"
        case .settings: "wrench.and.screwdriver.fill"
        }
    }
}

enum CoreRestartIntent: Equatable, Sendable {
    case startController
    case restartController
    case restartActiveRuntime

    static func resolve(isStarted: Bool, isCoreRunning: Bool) -> Self {
        if isStarted {
            return .restartActiveRuntime
        }
        return isCoreRunning ? .restartController : .startController
    }
}

enum CoreStatusPresentation {
    static func runtimeText(isStarted: Bool, isCoreRunning: Bool) -> String {
        if isStarted {
            return "VPN Active"
        }
        return isCoreRunning ? "Controller Running" : "Stopped"
    }
}

public enum OutboundMode: String, CaseIterable, Identifiable, Sendable {
    case rule
    case global
    case direct

    public var id: Self { self }

    public var title: String {
        AppLanguage.english.text(titleKey)
    }

    public var titleKey: AppString {
        switch self {
        case .rule: .rule
        case .global: .global
        case .direct: .direct
        }
    }
}

public enum NetworkEgressKind: String, Equatable, Sendable {
    case detecting
    case direct
    case proxy
    case systemTunnel
    case unavailable

    var titleKey: AppString {
        switch self {
        case .detecting: .detectingEgress
        case .direct: .directEgress
        case .proxy: .proxyEgress
        case .systemTunnel: .systemTunnelEgress
        case .unavailable: .unavailableEgress
        }
    }

    func title(language: AppLanguage) -> String {
        language.text(titleKey)
    }
}

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: Self { self }

    public var title: String {
        rawValue.capitalized
    }

    public func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system: systemColorScheme
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum NexoraAccent: String, CaseIterable, Identifiable, Sendable {
    case terracotta
    case cocoa
    case sand
    case ocean
    case cobalt
    case iris
    case violet
    case orchid
    case plum
    case slate
    case graphite

    public var id: Self { self }

    public var title: String {
        switch self {
        case .terracotta: "Terracotta"
        case .cocoa: "Cocoa"
        case .sand: "Sand"
        case .ocean: "Ocean"
        case .cobalt: "Cobalt"
        case .iris: "Iris"
        case .violet: "Violet"
        case .orchid: "Orchid"
        case .plum: "Plum"
        case .slate: "Slate"
        case .graphite: "Graphite"
        }
    }

    public func color(for colorScheme: ColorScheme) -> Color {
        switch (self, colorScheme) {
        case (.terracotta, .dark): Color(red: 0.80, green: 0.50, blue: 0.39)
        case (.terracotta, _): Color(red: 0.62, green: 0.34, blue: 0.27)
        case (.cocoa, .dark): Color(red: 0.71, green: 0.58, blue: 0.50)
        case (.cocoa, _): Color(red: 0.43, green: 0.32, blue: 0.27)
        case (.sand, .dark): Color(red: 0.78, green: 0.68, blue: 0.49)
        case (.sand, _): Color(red: 0.50, green: 0.40, blue: 0.23)
        case (.ocean, .dark): Color(red: 0.38, green: 0.68, blue: 0.86)
        case (.ocean, _): Color(red: 0.18, green: 0.45, blue: 0.68)
        case (.cobalt, .dark): Color(red: 0.43, green: 0.56, blue: 0.91)
        case (.cobalt, _): Color(red: 0.23, green: 0.35, blue: 0.70)
        case (.iris, .dark): Color(red: 0.57, green: 0.49, blue: 0.87)
        case (.iris, _): Color(red: 0.38, green: 0.30, blue: 0.67)
        case (.violet, .dark): Color(red: 0.69, green: 0.45, blue: 0.84)
        case (.violet, _): Color(red: 0.48, green: 0.28, blue: 0.63)
        case (.orchid, .dark): Color(red: 0.81, green: 0.48, blue: 0.71)
        case (.orchid, _): Color(red: 0.58, green: 0.29, blue: 0.49)
        case (.plum, .dark): Color(red: 0.70, green: 0.44, blue: 0.58)
        case (.plum, _): Color(red: 0.48, green: 0.26, blue: 0.37)
        case (.slate, .dark): Color(red: 0.58, green: 0.64, blue: 0.72)
        case (.slate, _): Color(red: 0.32, green: 0.39, blue: 0.49)
        case (.graphite, .dark): Color.white.opacity(0.72)
        case (.graphite, _): Color.black.opacity(0.62)
        }
    }
}

public enum ProfileValidationKind: String, Sendable {
    case notValidated
    case checking
    case valid
    case invalid
}

public struct ProfileValidationState: Equatable, Sendable {
    public let kind: ProfileValidationKind
    public let message: String?
    public let checkedAt: Date?

    public static let notValidated = ProfileValidationState(
        kind: .notValidated,
        message: nil,
        checkedAt: nil
    )

    public static let checking = ProfileValidationState(
        kind: .checking,
        message: nil,
        checkedAt: nil
    )

    public static func valid(checkedAt: Date = Date()) -> ProfileValidationState {
        ProfileValidationState(kind: .valid, message: nil, checkedAt: checkedAt)
    }

    public static func invalid(
        _ message: String,
        checkedAt: Date = Date()
    ) -> ProfileValidationState {
        ProfileValidationState(kind: .invalid, message: message, checkedAt: checkedAt)
    }

    public func title(language: AppLanguage) -> String {
        switch kind {
        case .notValidated:
            language.text(.notValidated)
        case .checking:
            language.text(.checking)
        case .valid:
            language.text(.valid)
        case .invalid:
            language.text(.invalid)
        }
    }

    public var symbol: String {
        switch kind {
        case .notValidated:
            "shield"
        case .checking:
            "arrow.triangle.2.circlepath"
        case .valid:
            "checkmark.shield.fill"
        case .invalid:
            "exclamationmark.triangle.fill"
        }
    }
}

enum ProfileHealthFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case needsFix
    case notChecked
    case valid

    var id: Self { self }

    func matches(_ state: ProfileValidationState) -> Bool {
        switch self {
        case .all:
            true
        case .needsFix:
            state.kind == .invalid
        case .notChecked:
            state.kind == .notValidated || state.kind == .checking
        case .valid:
            state.kind == .valid
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all:
            language.text(.allProfiles)
        case .needsFix:
            language.text(.invalid)
        case .notChecked:
            language.text(.notValidated)
        case .valid:
            language.text(.valid)
        }
    }
}

enum ProxyGroupKind: String, Codable, Sendable {
    case selector
    case urlTest
    case fallback
    case loadBalance
    case unknown

    init(mihomoType: String?) {
        switch mihomoType?.lowercased() {
        case "selector":
            self = .selector
        case "urltest", "url-test":
            self = .urlTest
        case "fallback":
            self = .fallback
        case "loadbalance", "load-balance":
            self = .loadBalance
        default:
            self = .unknown
        }
    }

    var isAutomatic: Bool {
        switch self {
        case .urlTest, .fallback, .loadBalance:
            true
        case .selector, .unknown:
            false
        }
    }
}

struct ProxyNode: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let region: String
    var latency: Int?
    var isSelected: Bool
    var isGroup: Bool = false
}

enum ProxyNodeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case selected
    case untested
    case slow

    static let slowLatencyThreshold = 350

    var id: Self { self }

    func matches(_ node: ProxyNode) -> Bool {
        return switch self {
        case .all:
            true
        case .selected:
            node.isSelected
        case .untested:
            node.latency == nil && !node.isGroup && isConcrete(node)
        case .slow:
            (node.latency ?? 0) >= Self.slowLatencyThreshold && !node.isGroup
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all: language.text(.allNodes)
        case .selected: language.text(.selectedOnly)
        case .untested: language.text(.untested)
        case .slow: language.text(.slowNodes)
        }
    }

    private func isConcrete(_ node: ProxyNode) -> Bool {
        !["DIRECT", "REJECT", "PASS", "COMPATIBLE"].contains(node.name.uppercased())
    }
}

struct ProxyGroup: Identifiable {
    var id: String { name }
    let name: String
    let policy: String
    var kind: ProxyGroupKind = .unknown
    var testURL: String? = nil
    var nodes: [ProxyNode]
}

struct ProxyGroupExpansionState: Equatable, Sendable {
    private var collapsedGroupNames: Set<String> = []

    func isExpanded(_ groupName: String) -> Bool {
        !collapsedGroupNames.contains(groupName)
    }

    mutating func toggle(_ groupName: String) {
        if collapsedGroupNames.contains(groupName) {
            collapsedGroupNames.remove(groupName)
        } else {
            collapsedGroupNames.insert(groupName)
        }
    }
}

enum MenuBarQuickAccessPolicy {
    static let selectorName = "Mutdot"
    static let visibleConnectionControlCount = 1
    static let showsSystemProxyToggle = false
    static let showsTunToggle = false
    static let showsOpenMainWindowButton = false
    static let clipsNodeViewport = true

    static let panelWidth: CGFloat = 360
    static let outerPadding: CGFloat = 12
    static let topInset = outerPadding
    static let bottomInset = outerPadding
    static let sectionSpacing: CGFloat = 10
    static let headerHeight: CGFloat = 66
    static let mainControlHeight: CGFloat = 72
    static let nodeHeaderHeight: CGFloat = 20
    static let nodeHeaderSpacing: CGFloat = 8
    static let nodeViewportHeight: CGFloat = 244

    static var requiredContentHeight: CGFloat {
        topInset
            + bottomInset
            + (sectionSpacing * 2)
            + headerHeight
            + mainControlHeight
            + nodeHeaderHeight
            + nodeHeaderSpacing
            + nodeViewportHeight
    }

    static var panelHeight: CGFloat {
        requiredContentHeight
    }
}

public enum MenuBarPanelMotion {
    public static let usesCustomWindowAnimator = true
    public static let usesCustomContentFade = false
    public static let startsWindowTransparent = true
    public static let respectsReducedMotion = true
    public static let fadeInDuration: TimeInterval = 0.30
    public static let fadeOutDuration: TimeInterval = 0.24
}

struct ConnectionEntry: Identifiable {
    let id = UUID()
    var remoteID: String? = nil
    let host: String
    let rule: String
    let chain: String
    let upload: String
    let download: String
}
