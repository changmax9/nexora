import AppIntents
import ClashGlassCore
import Foundation

// These intents execute in the application so every entry point uses the same
// runtime, transition queue, proxy snapshot, and privileged TUN authorization.
struct ConnectNexoraIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect Nexora"
    static let description = IntentDescription("Start the connection using the selected Nexora configuration.")
    static var openAppWhenRun: Bool { true }
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppStore.shared.setConnectionEnabledForAutomation(true)
        return .result(dialog: "Nexora is connected.")
    }
}

struct DisconnectNexoraIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect Nexora"
    static let description = IntentDescription("Stop the Nexora connection and restore the previous system proxy settings.")
    static var openAppWhenRun: Bool { true }
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppStore.shared.setConnectionEnabledForAutomation(false)
        return .result(dialog: "Nexora is disconnected.")
    }
}

struct EnableNexoraTUNIntent: AppIntent {
    static let title: LocalizedStringResource = "Enable Nexora TUN"
    static let description = IntentDescription("Enable Nexora TUN. macOS may request administrator approval the first time.")
    static var openAppWhenRun: Bool { true }
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        try await store.setTUNEnabledForAutomation(true)
        let dialog: IntentDialog = store.isStarted
            ? "Nexora TUN is enabled."
            : "Nexora TUN will be enabled the next time you connect."
        return .result(dialog: dialog)
    }
}

struct DisableNexoraTUNIntent: AppIntent {
    static let title: LocalizedStringResource = "Disable Nexora TUN"
    static let description = IntentDescription("Disable Nexora TUN while keeping an active Nexora connection in system proxy mode.")
    static var openAppWhenRun: Bool { true }
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppStore.shared.setTUNEnabledForAutomation(false)
        return .result(dialog: "Nexora TUN is disabled.")
    }
}

struct NexoraProxyNodeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Proxy Node"
    static let defaultQuery = NexoraProxyNodeQuery()

    let id: String
    let name: String
    let groupName: String

    init(node: AutomationProxyNode) {
        id = node.id
        name = node.name
        groupName = node.groupName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(groupName)")
    }
}

struct NexoraProxyNodeQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [NexoraProxyNodeEntity] {
        let nodes = try await AppStore.shared.automationProxyNodes()
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Missing IDs remain missing: a shortcut saved for an old profile must
        // never silently select a same-named node from a different profile.
        return identifiers.compactMap { byID[$0] }.map(NexoraProxyNodeEntity.init)
    }

    func suggestedEntities() async throws -> [NexoraProxyNodeEntity] {
        try await AppStore.shared.automationProxyNodes().map(NexoraProxyNodeEntity.init)
    }

    func entities(matching string: String) async throws -> [NexoraProxyNodeEntity] {
        let nodes = try await AppStore.shared.automationProxyNodes()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes.map(NexoraProxyNodeEntity.init) }
        let exact = nodes.filter {
            $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                || "\($0.groupName) / \($0.name)".compare(
                    query, options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }
        // Return every match for Siri to disambiguate; never choose an
        // arbitrary group when the subscription repeats a node's name.
        if !exact.isEmpty { return exact.map(NexoraProxyNodeEntity.init) }
        return nodes.filter {
            $0.name.localizedStandardContains(query)
                || "\($0.groupName) / \($0.name)".localizedStandardContains(query)
        }.map(NexoraProxyNodeEntity.init)
    }
}

struct SelectNexoraProxyNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Select Nexora Proxy Node"
    static let description = IntentDescription("Select a node in the current Nexora configuration. This does not start a VPN connection.")
    static var openAppWhenRun: Bool { true }
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(
        title: "Proxy Node",
        requestValueDialog: "Which Nexora proxy node would you like to use?",
        requestDisambiguationDialog: "Which proxy group should use this node?"
    )
    var node: NexoraProxyNodeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Select \(\.$node)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppStore.shared.selectProxyForAutomation(id: node.id)
        return .result(dialog: "Nexora selected \(node.name) in \(node.groupName).")
    }
}

struct NexoraAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectNexoraIntent(),
            phrases: ["Connect \(.applicationName)", "Turn on \(.applicationName)"],
            shortTitle: "Connect",
            systemImageName: "network"
        )
        AppShortcut(
            intent: DisconnectNexoraIntent(),
            phrases: ["Disconnect \(.applicationName)", "Turn off \(.applicationName)"],
            shortTitle: "Disconnect",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: EnableNexoraTUNIntent(),
            phrases: ["Enable TUN in \(.applicationName)", "Turn on \(.applicationName) TUN"],
            shortTitle: "Enable TUN",
            systemImageName: "shield.lefthalf.filled"
        )
        AppShortcut(
            intent: DisableNexoraTUNIntent(),
            phrases: ["Disable TUN in \(.applicationName)", "Turn off \(.applicationName) TUN"],
            shortTitle: "Disable TUN",
            systemImageName: "shield.slash"
        )
        AppShortcut(
            intent: SelectNexoraProxyNodeIntent(),
            phrases: [
                "Select a node in \(.applicationName)",
                "Use \(\.$node) in \(.applicationName)",
            ],
            shortTitle: "Select Node",
            systemImageName: "point.3.connected.trianglepath.dotted"
        )
    }
}
