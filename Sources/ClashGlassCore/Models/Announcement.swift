import Foundation

public enum AnnouncementKind: String, Codable, Equatable, Sendable, CaseIterable {
    case notice
    case update
    case warning
    case maintenance

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AnnouncementKind(rawValue: raw) ?? .notice
    }

    public var symbol: String {
        switch self {
        case .notice: "megaphone.fill"
        case .update: "sparkles"
        case .warning: "exclamationmark.triangle.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        }
    }
}

public enum AnnouncementDisplayPolicy: String, Codable, Equatable, Sendable {
    case once
    case daily

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AnnouncementDisplayPolicy(rawValue: raw) ?? .once
    }
}

public struct AnnouncementLocalization: Codable, Equatable, Sendable {
    public let title: String?
    public let body: String?
    public let badge: String?
    public let actionTitle: String?

    public init(
        title: String? = nil,
        body: String? = nil,
        badge: String? = nil,
        actionTitle: String? = nil
    ) {
        self.title = title
        self.body = body
        self.badge = badge
        self.actionTitle = actionTitle
    }
}

public struct AnnouncementContent: Equatable, Sendable {
    public let title: String
    public let body: String
    public let badge: String?
    public let actionTitle: String?

    public init(
        title: String,
        body: String,
        badge: String? = nil,
        actionTitle: String? = nil
    ) {
        self.title = title
        self.body = body
        self.badge = badge
        self.actionTitle = actionTitle
    }
}

public struct Announcement: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: AnnouncementKind
    public let title: String
    public let body: String
    public let badge: String?
    public let publishedAt: Date?
    public let startsAt: Date?
    public let expiresAt: Date?
    public let minVersion: String?
    public let maxVersion: String?
    public let displayPolicy: AnnouncementDisplayPolicy
    public let actionTitle: String?
    public let actionURL: String?
    public let localizations: [String: AnnouncementLocalization]?

    public init(
        id: String,
        kind: AnnouncementKind = .notice,
        title: String,
        body: String,
        badge: String? = nil,
        publishedAt: Date? = nil,
        startsAt: Date? = nil,
        expiresAt: Date? = nil,
        minVersion: String? = nil,
        maxVersion: String? = nil,
        displayPolicy: AnnouncementDisplayPolicy = .once,
        actionTitle: String? = nil,
        actionURL: String? = nil,
        localizations: [String: AnnouncementLocalization]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.badge = badge
        self.publishedAt = publishedAt
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        self.minVersion = minVersion
        self.maxVersion = maxVersion
        self.displayPolicy = displayPolicy
        self.actionTitle = actionTitle
        self.actionURL = actionURL
        self.localizations = localizations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(AnnouncementKind.self, forKey: .kind) ?? .notice
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        minVersion = try container.decodeIfPresent(String.self, forKey: .minVersion)
        maxVersion = try container.decodeIfPresent(String.self, forKey: .maxVersion)
        displayPolicy = try container.decodeIfPresent(AnnouncementDisplayPolicy.self, forKey: .displayPolicy) ?? .once
        actionTitle = try container.decodeIfPresent(String.self, forKey: .actionTitle)
        actionURL = try container.decodeIfPresent(String.self, forKey: .actionURL)
        localizations = try container.decodeIfPresent([String: AnnouncementLocalization].self, forKey: .localizations)
    }

    public var validatedActionURL: URL? {
        guard let raw = Self.nonEmptyTrimmed(actionURL),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

    public func resolvedContent(for language: AppLanguage) -> AnnouncementContent {
        let resolvedCode = language.resolvedLanguage.rawValue
        let baseCode = resolvedCode.split(separator: "-").first.map(String.init)
        let exact = localizations?[resolvedCode]
        let base = baseCode.flatMap { localizations?[$0] }

        func translation(_ field: KeyPath<AnnouncementLocalization, String?>) -> String? {
            Self.nonEmptyTrimmed(exact?[keyPath: field]) ?? Self.nonEmptyTrimmed(base?[keyPath: field])
        }

        return AnnouncementContent(
            title: translation(\.title) ?? title,
            body: translation(\.body) ?? body,
            badge: translation(\.badge) ?? Self.nonEmptyTrimmed(badge),
            actionTitle: translation(\.actionTitle) ?? Self.nonEmptyTrimmed(actionTitle)
        )
    }

    public func isActive(at now: Date, appVersion: String?) -> Bool {
        guard Self.nonEmptyTrimmed(id) != nil,
              Self.nonEmptyTrimmed(title) != nil,
              Self.nonEmptyTrimmed(body) != nil else {
            return false
        }
        if let startsAt, now < startsAt {
            return false
        }
        if let expiresAt, now >= expiresAt {
            return false
        }
        if let minVersion = Self.nonEmptyTrimmed(minVersion) {
            guard let appVersion = Self.nonEmptyTrimmed(appVersion),
                  AnnouncementVersionComparator.compare(appVersion, minVersion) != .orderedAscending else {
                return false
            }
        }
        if let maxVersion = Self.nonEmptyTrimmed(maxVersion) {
            guard let appVersion = Self.nonEmptyTrimmed(appVersion),
                  AnnouncementVersionComparator.compare(appVersion, maxVersion) != .orderedDescending else {
                return false
            }
        }
        return true
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct AnnouncementEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let announcement: Announcement?

    public init(schemaVersion: Int, announcement: Announcement?) {
        self.schemaVersion = schemaVersion
        self.announcement = announcement
    }
}

public enum AnnouncementVersionComparator {
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = components(from: lhs)
        let rightParts = components(from: rhs)
        let count = max(leftParts.count, rightParts.count)
        for index in 0..<count {
            let left = index < leftParts.count ? leftParts[index] : 0
            let right = index < rightParts.count ? rightParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(from version: String) -> [Int] {
        var trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        return trimmed.split(separator: ".").map { segment in
            let digits = segment.prefix(while: \.isWholeNumber)
            return Int(digits) ?? 0
        }
    }
}

public enum AnnouncementDecoder {
    public static let maximumPayloadBytes = 65_536

    public enum DecodingError: Error, Equatable, Sendable {
        case payloadTooLarge
        case unsupportedSchemaVersion(Int)
    }

    public static func decode(_ data: Data) throws -> Announcement? {
        guard data.count <= maximumPayloadBytes else {
            throw DecodingError.payloadTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = parseISO8601Date(string) {
                return date
            }
            throw Swift.DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date string: \(string)"
            )
        }
        let envelope = try decoder.decode(AnnouncementEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else {
            throw DecodingError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return envelope.announcement
    }

    private static func parseISO8601Date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}
