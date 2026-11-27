import Foundation

/// The identifier includes the profile and selector so Siri cannot reuse a
/// selection from a different subscription or silently choose a duplicate name.
public struct AutomationProxyNode: Identifiable, Codable, Equatable, Sendable {
    public static let catalogDidChange = Notification.Name("NexoraAutomationCatalogDidChange")
    public let profileID: String
    public let groupName: String
    public let name: String

    public init(profileID: String, groupName: String, name: String) {
        self.profileID = profileID
        self.groupName = groupName
        self.name = name
    }

    public var id: String {
        // An ordered array avoids ambiguous separators in user-defined names.
        (try? JSONEncoder().encode([profileID, groupName, name]).base64EncodedString()) ?? ""
    }
}

public enum AutomationControlError: Error, LocalizedError, Equatable {
    case operationFailed(String)
    case nodeUnavailable

    public var errorDescription: String? {
        switch self {
        case let .operationFailed(message): message
        case .nodeUnavailable:
            "This node is no longer available in the selected profile. Refresh the node list and choose again."
        }
    }
}
