import Foundation

public struct AnnouncementService: Sendable {
    public static let defaultFeedURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/changmax9/nexora/announcements/current.json")!,
        URL(string: "https://api.github.com/repos/changmax9/nexora/contents/current.json?ref=announcements")!,
    ]

    public let feedURLs: [URL]
    public let session: URLSession
    public let localOverridePath: String?

    public static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }

    public init(
        feedURLs: [URL] = defaultFeedURLs,
        session: URLSession = defaultSession(),
        localOverridePath: String? = ProcessInfo.processInfo.environment["NEXORA_ANNOUNCEMENT_FILE"]
    ) {
        self.feedURLs = feedURLs
        self.session = session
        self.localOverridePath = localOverridePath
    }

    public func fetchLatestAnnouncement() async throws -> Announcement? {
        try Task.checkCancellation()
        let limit = AnnouncementDecoder.maximumPayloadBytes
        if let localOverridePath, !localOverridePath.isEmpty {
            let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: localOverridePath))
            defer { try? file.close() }
            let data = try file.read(upToCount: limit + 1) ?? Data()
            return try AnnouncementDecoder.decode(data)
        }

        var lastError: Error?
        for url in feedURLs {
            do {
                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 8
                )
                request.setValue("Nexora", forHTTPHeaderField: "User-Agent")
                if url.host == "api.github.com" {
                    request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
                }

                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw AnnouncementFetchError.unexpectedStatus(statusCode)
                }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < limit else { throw AnnouncementDecoder.DecodingError.payloadTooLarge }
                    data.append(byte)
                }
                return try AnnouncementDecoder.decode(data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        return nil
    }
}

enum AnnouncementFetchError: Error, Equatable, Sendable {
    case unexpectedStatus(Int)
}

final class AnnouncementDismissalStore {
    static let storageKey = "nexora.announcementDismissals.v1"
    static let maximumEntries = 50

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func shouldPresent(
        _ announcement: Announcement,
        at now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let dismissals = storedDismissals()
        guard let dismissedTimestamp = dismissals[announcement.id] else {
            return true
        }
        switch announcement.displayPolicy {
        case .once:
            return false
        case .daily:
            let dismissedDate = Date(timeIntervalSince1970: dismissedTimestamp)
            return !calendar.isDate(dismissedDate, inSameDayAs: now)
        }
    }

    func markDismissed(_ announcement: Announcement, at now: Date = Date()) {
        var dismissals = storedDismissals()
        dismissals[announcement.id] = now.timeIntervalSince1970
        if dismissals.count > Self.maximumEntries {
            let retained = dismissals
                .sorted { $0.value > $1.value }
                .prefix(Self.maximumEntries)
            dismissals = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        }
        userDefaults.set(dismissals, forKey: Self.storageKey)
    }

    func storedDismissals() -> [String: TimeInterval] {
        userDefaults.dictionary(forKey: Self.storageKey) as? [String: TimeInterval] ?? [:]
    }
}
