import Foundation
import Testing
@testable import ClashGlassCore

@Suite(.serialized)
struct AnnouncementTests {
    @Test func decoderParsesValidAndNullEnvelopesAndResistsUnknownFields() throws {
        let validJSON = """
        {
          "schemaVersion": 1,
          "announcement": {
            "id": "20261127-notice",
            "kind": "future-unknown-kind",
            "title": "系统维护通知",
            "body": "今晚 02:00 进行服务器例行维护。",
            "badge": "维护公告",
            "publishedAt": "2026-11-27T14:30:00.123Z",
            "startsAt": "2026-11-27T14:00:00Z",
            "expiresAt": "2026-12-01T00:00:00Z",
            "minVersion": "1.0.0",
            "maxVersion": "2.0.0",
            "displayPolicy": "future-policy",
            "actionTitle": "查看详情",
            "actionURL": "https://github.com/changmax9/nexora/releases",
            "localizations": {
              "en": {
                "title": "Maintenance Notice",
                "body": "Scheduled maintenance at 02:00.",
                "badge": "Maintenance",
                "actionTitle": "Details"
              }
            }
          }
        }
        """
        let decoded = try #require(try AnnouncementDecoder.decode(Data(validJSON.utf8)))
        #expect(decoded.id == "20261127-notice")
        #expect(decoded.kind == .notice)
        #expect(decoded.displayPolicy == .once)
        #expect(decoded.validatedActionURL?.absoluteString == "https://github.com/changmax9/nexora/releases")

        let nullJSON = #"{"schemaVersion": 1, "announcement": null}"#
        #expect(try AnnouncementDecoder.decode(Data(nullJSON.utf8)) == nil)
    }

    @Test func decoderRejectsUnsupportedSchemaAndOversizedPayloads() throws {
        let badSchema = #"{"schemaVersion": 2, "announcement": null}"#
        #expect(throws: AnnouncementDecoder.DecodingError.unsupportedSchemaVersion(2)) {
            try AnnouncementDecoder.decode(Data(badSchema.utf8))
        }

        let oversized = Data(repeating: 0x20, count: AnnouncementDecoder.maximumPayloadBytes + 1)
        #expect(throws: AnnouncementDecoder.DecodingError.payloadTooLarge) {
            try AnnouncementDecoder.decode(oversized)
        }
    }

    @Test func actionURLValidationRejectsNonHTTPSAndCredentials() {
        let valid = Announcement(id: "1", title: "T", body: "B", actionURL: "https://example.com/path?a=1")
        #expect(valid.validatedActionURL != nil)

        for unsafe in [
            "http://example.com/path",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "https://user:secret@example.com/path",
            "https://user@example.com",
            "   ",
            "",
        ] {
            let candidate = Announcement(id: "1", title: "T", body: "B", actionURL: unsafe)
            #expect(candidate.validatedActionURL == nil, "Expected \(unsafe) to be rejected")
        }
    }

    @Test func localizationAndVersionTargetingWorkAcrossEdgeCases() {
        #expect(AnnouncementVersionComparator.compare("1.0.10", "1.0.2") == .orderedDescending)
        #expect(AnnouncementVersionComparator.compare("v1.0.1", "1.0.1") == .orderedSame)
        #expect(AnnouncementVersionComparator.compare("1.0", "1.0.0") == .orderedSame)
        #expect(AnnouncementVersionComparator.compare("0.9.9", "1.0.0") == .orderedAscending)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let announcement = Announcement(
            id: "2026-test",
            kind: .warning,
            title: "默认标题",
            body: "默认正文",
            badge: "重要",
            startsAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(60),
            minVersion: "1.0.0",
            maxVersion: "1.0.10",
            actionTitle: "了解更多",
            localizations: [
                "en": AnnouncementLocalization(title: "English Title", body: "English Body"),
                "zh": AnnouncementLocalization(badge: "公告"),
            ]
        )

        #expect(announcement.isActive(at: now, appVersion: "1.0.2"))
        #expect(!announcement.isActive(at: now, appVersion: "0.9.9"))
        #expect(!announcement.isActive(at: now, appVersion: "1.0.11"))
        #expect(!announcement.isActive(at: now, appVersion: nil))
        #expect(!announcement.isActive(at: now.addingTimeInterval(-120), appVersion: "1.0.2"))
        #expect(!announcement.isActive(at: now.addingTimeInterval(120), appVersion: "1.0.2"))

        let blankTitle = Announcement(id: "1", title: "  ", body: "Body")
        #expect(!blankTitle.isActive(at: now, appVersion: "1.0.0"))

        let enContent = announcement.resolvedContent(for: .english)
        #expect(enContent.title == "English Title")
        #expect(enContent.body == "English Body")
        #expect(enContent.badge == "重要")
        #expect(enContent.actionTitle == "了解更多")

        let zhHansContent = announcement.resolvedContent(for: .simplifiedChinese)
        #expect(zhHansContent.title == "默认标题")
        #expect(zhHansContent.badge == "公告")
    }

    @Test func dismissalStoreSupportsOnceDailyAndRetentionCap() throws {
        let suiteName = "AnnouncementDismissal-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AnnouncementDismissalStore(userDefaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1Morning = Date(timeIntervalSince1970: 1_700_006_400) // 2023-11-15T00:00:00Z + offset
        let day1Evening = day1Morning.addingTimeInterval(3600)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1Morning)!

        let onceItem = Announcement(id: "once-1", title: "T", body: "B", displayPolicy: .once)
        #expect(store.shouldPresent(onceItem, at: day1Morning, calendar: calendar))
        store.markDismissed(onceItem, at: day1Morning)
        #expect(!store.shouldPresent(onceItem, at: day1Evening, calendar: calendar))
        #expect(!store.shouldPresent(onceItem, at: day2, calendar: calendar))

        let dailyItem = Announcement(id: "daily-1", title: "T", body: "B", displayPolicy: .daily)
        #expect(store.shouldPresent(dailyItem, at: day1Morning, calendar: calendar))
        store.markDismissed(dailyItem, at: day1Morning)
        #expect(!store.shouldPresent(dailyItem, at: day1Evening, calendar: calendar))
        #expect(store.shouldPresent(dailyItem, at: day2, calendar: calendar))

        for index in 0..<60 {
            let item = Announcement(id: "cap-\(index)", title: "T", body: "B")
            store.markDismissed(item, at: day1Morning.addingTimeInterval(TimeInterval(index)))
        }
        let retained = store.storedDismissals()
        #expect(retained.count == AnnouncementDismissalStore.maximumEntries)
        #expect(retained["cap-59"] != nil)
        #expect(retained["once-1"] == nil)
    }

    @Test func serviceFallsBackToGitHubAPIAndSupportsLocalOverrideFile() async throws {
        let primaryURL = URL(string: "https://announcement.test/primary.json")!
        let fallbackURL = URL(string: "https://api.github.com/repos/test/nexora/contents/current.json?ref=announcements")!
        let validEnvelope = Data(#"{"schemaVersion":1,"announcement":{"id":"fallback-1","title":"Hi","body":"Body"}}"#.utf8)

        AnnouncementMockURLProtocol.handler.withLock {
            $0 = { request in
                if request.url == primaryURL {
                    let response = HTTPURLResponse(url: primaryURL, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (.success((Data(), response)))
                }
                #expect(request.url == fallbackURL)
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
                #expect(request.value(forHTTPHeaderField: "User-Agent") == "Nexora")
                let response = HTTPURLResponse(url: fallbackURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return .success((validEnvelope, response))
            }
        }
        defer { AnnouncementMockURLProtocol.handler.withLock { $0 = nil } }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnnouncementMockURLProtocol.self]
        let service = AnnouncementService(
            feedURLs: [primaryURL, fallbackURL],
            session: URLSession(configuration: config),
            localOverridePath: nil
        )

        let fetched = try await service.fetchLatestAnnouncement()
        #expect(fetched?.id == "fallback-1")

        // Null withdrawal on primary succeeds immediately without querying fallback.
        let fallbackCalled = LockedBox(false)
        AnnouncementMockURLProtocol.handler.withLock {
            $0 = { request in
                if request.url == primaryURL {
                    let nullBody = Data(#"{"schemaVersion":1,"announcement":null}"#.utf8)
                    let response = HTTPURLResponse(url: primaryURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return .success((nullBody, response))
                }
                fallbackCalled.withLock { $0 = true }
                throw URLError(.cannotConnectToHost)
            }
        }
        #expect(try await service.fetchLatestAnnouncement() == nil)
        #expect(!fallbackCalled.withLock { $0 })

        // Local override file short-circuits networking.
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("announcement-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try Data(#"{"schemaVersion":1,"announcement":{"id":"local-1","title":"Local","body":"Preview"}}"#.utf8)
            .write(to: tempFile)
        let localService = AnnouncementService(
            feedURLs: [primaryURL],
            session: URLSession(configuration: config),
            localOverridePath: tempFile.path
        )
        let localItem = try await localService.fetchLatestAnnouncement()
        #expect(localItem?.id == "local-1")
    }

    @Test func announcementServiceEnforcesTheSameByteLimitForFilesAndUnknownLengthResponses() async throws {
        let url = URL(string: "https://announcement.test/size")!
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnnouncementMockURLProtocol.self]
        let remote = AnnouncementService(feedURLs: [url], session: URLSession(configuration: config), localOverridePath: nil)
        let preview = AnnouncementService(localOverridePath: file.path)
        defer { AnnouncementMockURLProtocol.handler.withLock { $0 = nil } }
        let envelope = Data(#"{"schemaVersion":1,"announcement":null}"#.utf8)
        for extra in 0...1 {
            let padding = AnnouncementDecoder.maximumPayloadBytes + extra - envelope.count
            let data = envelope + Data(repeating: 0x20, count: padding)
            try data.write(to: file)
            AnnouncementMockURLProtocol.handler.withLock {
                $0 = { _ in .success((data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)) }
            }
            for service in [remote, preview] {
                if extra == 0 {
                    #expect(try await service.fetchLatestAnnouncement() == nil)
                } else {
                    await #expect(throws: AnnouncementDecoder.DecodingError.payloadTooLarge) {
                        try await service.fetchLatestAnnouncement()
                    }
                }
            }
        }
    }

    @MainActor
    @Test func cachedAnnouncementStartsAndExpiresDuringTheRefreshCooldown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let feed = root.appendingPathComponent("feed.json")
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = LockedBox(Date(timeIntervalSince1970: 1_700_000_000))
        let start = time.withLock { $0.addingTimeInterval(30) }
        let end = start.addingTimeInterval(60)
        let item = Announcement(id: "scheduled", title: "Title", body: "Body", startsAt: start, expiresAt: end)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(AnnouncementEnvelope(schemaVersion: 1, announcement: item)).write(to: feed)
        let store = AppStore(
            profileRepository: ManagedProfileRepository(rootURL: root),
            announcementService: AnnouncementService(localOverridePath: feed.path),
            nowProvider: { time.withLock { $0 } }, userDefaults: defaults, automaticallyMonitorsRuntime: false
        )
        await store.checkForAnnouncement()
        #expect(store.latestAnnouncement == nil)
        try FileManager.default.removeItem(at: feed)
        time.withLock { $0 = start }
        await store.checkForAnnouncement()
        #expect(store.activeAnnouncement?.id == item.id)
        time.withLock { $0 = end }
        await store.checkForAnnouncement()
        #expect(store.latestAnnouncement == nil)
        #expect(store.activeAnnouncement == nil)
    }

    @MainActor
    @Test func appStoreAnnouncementLifecycleCooldownRetryDismissalAndWithdrawal() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("announcement-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let suiteName = "AnnouncementStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let feedURL = URL(string: "https://announcement.test/store.json")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnnouncementMockURLProtocol.self]
        let service = AnnouncementService(
            feedURLs: [feedURL],
            session: URLSession(configuration: config),
            localOverridePath: nil
        )

        let currentTime = LockedBox(Date(timeIntervalSince1970: 1_700_000_000))
        let requestCount = LockedBox(0)

        let store = AppStore(
            profileRepository: ManagedProfileRepository(rootURL: rootURL),
            announcementService: service,
            appVersionProvider: { "1.0.2" },
            nowProvider: { currentTime.withLock { $0 } },
            userDefaults: defaults,
            automaticallyMonitorsRuntime: false
        )

        // 1. Offline failure stays silent and does NOT activate the 30-min cooldown.
        AnnouncementMockURLProtocol.handler.withLock {
            $0 = { _ in
                requestCount.withLock { $0 += 1 }
                return .failure(URLError(.notConnectedToInternet))
            }
        }
        await store.checkForAnnouncement()
        #expect(store.activeAnnouncement == nil)
        #expect(store.latestAnnouncement == nil)
        #expect(store.lastErrorMessage == nil)
        #expect(store.errorAlertMessage == nil)
        #expect(requestCount.withLock { $0 } == 1)

        // 2. Immediately after failure, reconnecting retries without waiting 30 minutes.
        let payloadV1 = Data(#"{"schemaVersion":1,"announcement":{"id":"notice-1","kind":"notice","title":"新功能上线","body":"支持全屏 Glass 公告。","displayPolicy":"once"}}"#.utf8)
        AnnouncementMockURLProtocol.handler.withLock {
            $0 = { _ in
                requestCount.withLock { $0 += 1 }
                let response = HTTPURLResponse(url: feedURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return .success((payloadV1, response))
            }
        }
        await store.checkForAnnouncement()
        #expect(requestCount.withLock { $0 } == 2)
        #expect(store.activeAnnouncement?.id == "notice-1")
        #expect(store.latestAnnouncement?.id == "notice-1")

        // 3. Successful fetch enforces 30-minute cooldown unless forced.
        currentTime.withLock { $0 = $0.addingTimeInterval(600) }
        await store.checkForAnnouncement()
        #expect(requestCount.withLock { $0 } == 2)

        // 4. Dismiss hides modal while preserving latestAnnouncement in Settings; reopen restores it.
        store.dismissActiveAnnouncement()
        #expect(store.activeAnnouncement == nil)
        #expect(store.latestAnnouncement?.id == "notice-1")

        await store.checkForAnnouncement(force: true)
        #expect(requestCount.withLock { $0 } == 3)
        #expect(store.activeAnnouncement == nil)

        store.reopenLatestAnnouncement()
        #expect(store.activeAnnouncement?.id == "notice-1")

        await store.checkForAnnouncement(force: true)
        #expect(store.activeAnnouncement?.id == "notice-1")
        #expect(requestCount.withLock { $0 } == 4)

        // 5. After 30 minutes, a withdrawal (announcement: null) clears both active and latest.
        currentTime.withLock { $0 = $0.addingTimeInterval(1801) }
        let nullPayload = Data(#"{"schemaVersion":1,"announcement":null}"#.utf8)
        AnnouncementMockURLProtocol.handler.withLock {
            $0 = { _ in
                requestCount.withLock { $0 += 1 }
                let response = HTTPURLResponse(url: feedURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return .success((nullPayload, response))
            }
        }
        await store.checkForAnnouncement()
        #expect(requestCount.withLock { $0 } == 5)
        #expect(store.activeAnnouncement == nil)
        #expect(store.latestAnnouncement == nil)

        AnnouncementMockURLProtocol.handler.withLock { $0 = nil }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private final class AnnouncementMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let handler = LockedBox<(@Sendable (URLRequest) throws -> Result<(Data, URLResponse), Error>)?>(nil)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let currentHandler = Self.handler.withLock { $0 }
        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            switch try currentHandler(request) {
            case let .success((data, response)):
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            case let .failure(error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
