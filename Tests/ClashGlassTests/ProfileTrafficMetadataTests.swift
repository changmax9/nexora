import Foundation
import Testing
@testable import ClashGlassCore

@Test func localProfileReadsRemainingBalanceWithoutInventingTotalOrPercentage() throws {
    let yaml = """
    proxies:
      - {name: '剩余流量：123.45 GB', type: ss}
      - {name: '距离下次重置剩余：28 天', type: ss}
      - {name: '套餐到期：2030-12-31', type: ss}
    """
    let date = Date(timeIntervalSince1970: 1_000)
    let usage = try #require(ProfileTrafficMetadata.usage(in: yaml, updatedAt: date))
    #expect(abs(try #require(usage.remainingGigabytes) - 123.45) < 0.000001)
    #expect(usage.remainingFraction == nil)
    #expect(usage.source == .configuration)
    #expect(usage.updatedAt == date)
}

@Test func localProfileReadsStructuredHeaderBeforeInformationalNodes() throws {
    let yaml = """
    subscription-userinfo: 'upload=10; download=15; total=100'
    proxies:
      - {name: '剩余流量：999 GB', type: ss}
    """
    let usage = try #require(ProfileTrafficMetadata.usage(in: yaml, updatedAt: .distantPast))
    #expect(usage.remainingBytes == 75)
    #expect(usage.remainingFraction == 0.75)
    #expect(usage.source == .configuration)
}

@Test func localProfileDoesNotMistakeServerNamesAndResetDatesForQuota() {
    for name in ["香港 10 GB", "GB Server", "距离下次重置剩余：28 天", "套餐到期：2030-12-31",
                 "剩余流量：-1 GB", "剩余流量：nan GB", "剩余流量：99999999999999 TB", "Remaining Traffic: 3 GB promo"] {
        let yaml = "proxies:\n  - name: '\(name)'\n"
        #expect(ProfileTrafficMetadata.usage(in: yaml, updatedAt: .distantPast) == nil)
    }
    #expect(ProfileTrafficMetadata.usage(in: "not: valid: yaml", updatedAt: .distantPast) == nil)
    #expect(ProfileTrafficMetadata.usage(in: "proxy-groups: [{name: '剩余流量：10 GB'}]", updatedAt: .distantPast) == nil)
    #expect(ProfileTrafficMetadata.usage(
        in: "proxies: [{name: '剩余流量：10 GB'}, {name: '剩余流量：20 GB'}]", updatedAt: .distantPast
    ) == nil)
}

@Test func localProfileQuotaSupportsExhaustionUnitsAndTraditionalChinese() throws {
    for (name, bytes) in [("剩餘流量：0 GB", Int64(0)), ("Remaining Traffic: 512 MiB", Int64(536_870_912)),
                          ("Data Left: 1.5 TB", Int64(1_649_267_441_664))] {
        let usage = try #require(ProfileTrafficMetadata.usage(
            in: "proxies: [{name: '\(name)'}]", updatedAt: .distantPast
        ))
        #expect(usage.remainingBytes == bytes)
        #expect(usage.remainingFraction == nil)
    }
}

@MainActor
@Test func importedAndPreviouslySavedLocalProfilesShowYAMLUsage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("config.yaml")
    try "proxies: [{name: '剩余流量：123.45 GB'}]".write(to: file, atomically: true, encoding: .utf8)
    let repository = ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed"))
    let profile = try await repository.importProfile(from: file) { _ in .success }
    #expect(profile.trafficUsage?.remainingGigabytes != nil)
    #expect(try repository.loadProfiles().first?.trafficUsage == profile.trafficUsage)

    // Simulate an existing registry created before local YAML metadata was supported.
    let registry = repository.rootURL.appendingPathComponent("profiles.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [String: Any])
    var entries = try #require(json["profiles"] as? [[String: Any]])
    entries[0].removeValue(forKey: "trafficUsage")
    json["profiles"] = entries
    try JSONSerialization.data(withJSONObject: json).write(to: registry, options: .atomic)
    let restored = try #require(repository.loadProfiles().first)
    #expect(restored.trafficUsage == profile.trafficUsage)
    #expect(restored.subscriptionURL == nil)
}

@Test func legacyTrafficSnapshotsDecodeAndRemainingOnlySnapshotsRoundTrip() throws {
    let oldJSON = Data(#"{"uploadBytes":10,"downloadBytes":15,"totalBytes":100,"updatedAt":0}"#.utf8)
    let oldUsage = try JSONDecoder().decode(ProfileTrafficUsage.self, from: oldJSON)
    #expect(oldUsage.remainingBytes == 75)
    #expect(oldUsage.source == nil)
    let balance = try #require(ProfileTrafficUsage(remainingBytes: 1_073_741_824, updatedAt: .distantPast))
    let roundTrip = try JSONDecoder().decode(ProfileTrafficUsage.self, from: JSONEncoder().encode(balance))
    #expect(roundTrip == balance)
    #expect(roundTrip.remainingGigabytes == 1)
    #expect(roundTrip.remainingFraction == nil)
}
