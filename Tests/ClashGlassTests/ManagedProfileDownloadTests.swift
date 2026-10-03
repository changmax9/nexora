import Foundation
import Testing
@testable import ClashGlassCore

@Test func managedProfileURLAcceptsSubscriptionLinksWithoutYAMLExtensions() throws {
    let url = try ManagedProfileDownloader.configurationURL(
        from: "  https://profiles.example.test/subscribe?token=abc&format=clash\n"
    )
    #expect(url.absoluteString == "https://profiles.example.test/subscribe?token=abc&format=clash")
    for input in ["", "profiles.example.test/config.yaml", "file:///tmp/config.yaml", "ftp://profiles.example.test/config.yaml", "https://"] {
        #expect(throws: ManagedProfileDownloadError.invalidURL) {
            try ManagedProfileDownloader.configurationURL(from: input)
        }
    }
}

@Test func managedProfileDownloadUsesServerFilenameAndPreservesYAML() async throws {
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let download = try await ManagedProfileDownloader(session: session).download(
        from: URL(string: "https://profiles.example.test/subscribe?token=abc")!
    )
    #expect(download.name == "Work")
    #expect(download.trafficUsage?.remainingGigabytes == 75)
    #expect(String(decoding: download.data, as: UTF8.self).contains("MATCH,DIRECT"))
}

@Test func managedProfileDownloadRejectsHTTPFailuresAndEmptyBodies() async throws {
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let downloader = ManagedProfileDownloader(session: session)
    await #expect(throws: ManagedProfileDownloadError.httpStatus(404)) {
        try await downloader.download(from: URL(string: "https://profiles.example.test/missing")!)
    }
    await #expect(throws: ManagedProfileDownloadError.emptyResponse) {
        try await downloader.download(from: URL(string: "https://profiles.example.test/empty")!)
    }
}

@Test func managedProfileDownloadDecodesTheProvidersUTF8FilenameWithoutAnExtension() async throws {
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let download = try await ManagedProfileDownloader(session: session).download(
        from: URL(string: "https://profiles.example.test/encoded-name")!
    )
    #expect(download.name == "示例订阅")
    #expect(download.trafficUsage?.remainingGigabytes == 75)
}

@Test func managedProfileDownloadRejectsHTTP200HealthMessagesAndErrorDocuments() async throws {
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    for path in ["health-message", "error-document", "node-list"] {
        await #expect(throws: ManagedProfileDownloadError.notConfiguration) {
            try await ManagedProfileDownloader(session: session).download(
                from: URL(string: "https://profiles.example.test/\(path)")!
            )
        }
    }
}

@MainActor
@Test func managedProfileHealthResponseDoesNotPersistAProfileOrChangeSelection() async throws {
    let fixture = try ProfileDownloadStoreFixture(rejectConfiguration: false)
    defer { fixture.cleanUp() }
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    await #expect(throws: ManagedProfileDownloadError.notConfiguration) {
        try await fixture.store.importManagedProfile(
            fromRemoteURL: URL(string: "https://profiles.example.test/health-message")!,
            downloader: ManagedProfileDownloader(session: session)
        )
    }
    #expect(fixture.store.managedProfiles.isEmpty)
    #expect(try fixture.repository.loadProfiles().isEmpty)
    #expect(fixture.store.selectedManagedProfileID == nil)
}

@Test func managedProfileFilenamePrefersUTF8AndTreatsItOnlyAsADisplayName() {
    let url = URL(string: "https://profiles.example.test/subscription")!
    let cases = [
        ("attachment; filename=\"fallback.yaml\"; filename*=UTF-8'zh'%E7%A4%BA%E4%BE%8B%E8%AE%A2%E9%98%85", "示例订阅"),
        ("attachment; filename=\"Folder/Work.yaml\"", "Work"),
        ("attachment; filename=\"Local Profile.yml\"", "Local Profile"),
        ("attachment; filename*=UTF-8''%ZZ; filename=\"Fallback.yaml\"", "Fallback"),
        ("inline", "profiles.example.test"),
    ]
    for (header, expected) in cases {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Disposition": header])!
        #expect(ManagedProfileDownloader.profileName(response: response, url: url) == expected)
    }
}

@MainActor
@Test func managedProfileRemoteImportValidatesAndStoresDownloadedConfiguration() async throws {
    let fixture = try ProfileDownloadStoreFixture(rejectConfiguration: false)
    defer { fixture.cleanUp() }
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }

    let imported = try await fixture.store.importManagedProfile(
        fromRemoteURL: URL(string: "https://profiles.example.test/subscribe")!,
        downloader: ManagedProfileDownloader(session: session)
    )
    #expect(imported)
    let profile = try #require(fixture.store.managedProfiles.first)
    #expect(profile.name == "Work")
    #expect(profile.trafficUsage?.remainingFraction == 0.75)
    #expect(profile.subscriptionURL == URL(string: "https://profiles.example.test/subscribe"))
    #expect(try fixture.repository.loadProfiles().first?.trafficUsage == profile.trafficUsage)
    #expect(fixture.store.selectedManagedProfileID == profile.id)
    #expect(fixture.store.validationState(for: profile.id).kind == .valid)
    #expect(try String(contentsOf: profile.managedConfigURL, encoding: .utf8).contains("MATCH,DIRECT"))
    #expect(fixture.store.lastErrorMessage == nil)
}

@MainActor
@Test func managedProfileUsageRefreshPreservesConfigurationAndSelection() async throws {
    let fixture = try ProfileDownloadStoreFixture(rejectConfiguration: false)
    defer { fixture.cleanUp() }
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let downloader = ManagedProfileDownloader(session: session)
    _ = try await fixture.store.importManagedProfile(
        fromRemoteURL: URL(string: "https://profiles.example.test/subscribe")!, downloader: downloader
    )
    let profile = try #require(fixture.store.managedProfiles.first)
    let originalConfiguration = try Data(contentsOf: profile.managedConfigURL)
    let isStarted = fixture.store.isStarted
    await fixture.store.refreshManagedProfileTrafficUsage(downloader: downloader)
    #expect(fixture.store.managedProfiles.first?.trafficUsage?.remainingFraction == 0.75)
    #expect(fixture.store.selectedManagedProfileID == profile.id)
    #expect(fixture.store.isStarted == isStarted)
    #expect(try Data(contentsOf: profile.managedConfigURL) == originalConfiguration)
    #expect(try fixture.repository.loadProfiles().first?.trafficUsage == fixture.store.managedProfiles.first?.trafficUsage)
    #expect(fixture.store.profileTrafficRefreshFailures.isEmpty)
    #expect(!fixture.store.isRefreshingProfileTrafficUsage)
}

@Test func managedProfileDownloadWithoutQuotaDoesNotInventUsage() async throws {
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let download = try await ManagedProfileDownloader(session: session).download(
        from: URL(string: "https://profiles.example.test/no-usage")!
    )
    #expect(download.trafficUsage == nil)
    #expect(!download.data.isEmpty)
}

@MainActor
@Test func managedProfileUsageRefreshKeepsLastSnapshotWhenProviderOmitsQuota() async throws {
    let fixture = try ProfileDownloadStoreFixture(rejectConfiguration: false)
    defer { fixture.cleanUp() }
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let downloader = ManagedProfileDownloader(session: session)
    _ = try await fixture.store.importManagedProfile(
        fromRemoteURL: URL(string: "https://profiles.example.test/no-usage")!, downloader: downloader
    )
    let profile = try #require(fixture.store.managedProfiles.first)
    let cachedUsage = try #require(ProfileTrafficUsage(
        subscriptionUserInfo: "upload=0; download=20; total=100", updatedAt: Date(timeIntervalSince1970: 1_000)
    ))
    try fixture.repository.updateTrafficUsage(cachedUsage, for: profile.id)
    await fixture.store.refreshManagedProfileTrafficUsage(downloader: downloader)
    #expect(try fixture.repository.loadProfiles().first?.trafficUsage == cachedUsage)
    #expect(fixture.store.profileTrafficRefreshFailures.contains(profile.id))
    #expect(!fixture.store.isRefreshingProfileTrafficUsage)
}

@MainActor
@Test func managedProfileRemoteImportLeavesRegistryUnchangedWhenValidationFails() async throws {
    let fixture = try ProfileDownloadStoreFixture(rejectConfiguration: true)
    defer { fixture.cleanUp() }
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }

    await #expect(throws: ManagedProfileError.validationFailed("configuration rejected")) {
        try await fixture.store.importManagedProfile(
            fromRemoteURL: URL(string: "https://profiles.example.test/subscribe")!,
            downloader: ManagedProfileDownloader(session: session)
        )
    }
    #expect(fixture.store.managedProfiles.isEmpty)
    #expect(try fixture.repository.loadProfiles().isEmpty)
    #expect(fixture.store.selectedManagedProfileID == nil)
    #expect(!fixture.store.isRuntimeTransitioning)
    #expect(fixture.store.lastErrorMessage == nil)
}

@MainActor
@Test func simultaneousQuotaRefreshesShareTheExistingRequest() async throws {
    let fixture = try ProfileDownloadStoreFixture(rejectConfiguration: false)
    defer { fixture.cleanUp() }
    let file = fixture.directory.appendingPathComponent("config.yaml")
    try "mixed-port: 7890".write(to: file, atomically: true, encoding: .utf8)
    _ = try await fixture.repository.importProfile(
        from: file, subscriptionURL: URL(string: "https://profiles.example.test/slow")
    ) { _ in .success }
    let store = AppStore(profileRepository: fixture.repository)
    let session = profileDownloadSession()
    defer { session.invalidateAndCancel() }
    let downloader = ManagedProfileDownloader(session: session)
    let first = Task { await store.refreshManagedProfileTrafficUsage(downloader: downloader) }
    for _ in 0..<1_000 {
        if store.isRefreshingProfileTrafficUsage { break }
        await Task.yield()
    }
    #expect(store.isRefreshingProfileTrafficUsage)
    await store.refreshManagedProfileTrafficUsage(downloader: downloader)
    #expect(store.isRefreshingProfileTrafficUsage)
    await first.value
    #expect(!store.isRefreshingProfileTrafficUsage)
    #expect(store.managedProfiles.first?.trafficUsage?.remainingGigabytes == 75)
}

@Test func managedProfileCancelledImportDoesNotPersistConfiguration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("config.yaml")
    try "mixed-port: 7890".write(to: fileURL, atomically: true, encoding: .utf8)
    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let task = Task { @MainActor in
        try await repository.importProfile(from: fileURL) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .success
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try repository.loadProfiles().isEmpty)
}

private func profileDownloadSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProfileDownloadURLProtocol.self]
    return URLSession(configuration: configuration)
}

@MainActor
private struct ProfileDownloadStoreFixture {
    let directory: URL
    let repository: ManagedProfileRepository
    let store: AppStore

    init(rejectConfiguration: Bool) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("fake-mihomo")
        let script = rejectConfiguration
            ? "#!/bin/sh\necho 'configuration rejected' >&2\nexit 1\n"
            : "#!/bin/sh\nexit 0\n"
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
        store = AppStore(
            coreService: MihomoCoreService(coreBinaryURL: executableURL),
            profileRepository: repository
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class ProfileDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "profiles.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.path == "/slow" {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { self.sendResponse() }
        } else {
            sendResponse()
        }
    }

    private func sendResponse() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: url.path == "/missing" ? 404 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Disposition": url.path == "/encoded-name"
                    ? "attachment;filename*=UTF-8''%E7%A4%BA%E4%BE%8B%E8%AE%A2%E9%98%85"
                    : "attachment; filename=\"Work.yaml\"",
                "Content-Type": "text/html; charset=UTF-8",
                "Subscription-Userinfo": url.path == "/no-usage" ? "" : "upload=5368709120; download=21474836480; total=107374182400",
            ]
        )!
        let configuration = "mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n"
        let content = request.value(forHTTPHeaderField: "User-Agent")?.lowercased().contains("clash") == true
            ? configuration
            : Data("ss://test-node".utf8).base64EncodedString()
        let data: Data
        switch url.path {
        case "/empty": data = Data()
        case "/health-message": data = Data("service ready".utf8)
        case "/error-document": data = Data(#"{"message":"Not a configuration"}"#.utf8)
        case "/node-list": data = Data(Data("ss://example-node".utf8).base64EncodedString().utf8)
        default: data = Data(content.utf8)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
