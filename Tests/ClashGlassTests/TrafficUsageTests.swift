import Foundation
import Testing
@testable import ClashGlassCore

@Test func trafficUsageDoesNotInventPercentagesWithoutTraffic() {
    #expect(!TrafficUsageTotals.zero.hasTraffic)
    #expect(TrafficUsageTotals.zero.uploadFraction == nil)
    #expect(TrafficUsageTotals.zero.downloadFraction == nil)
    #expect(TrafficUsageTotals(uploadBytes: -10, downloadBytes: -20) == .zero)
}

@Test func trafficUsageHandlesOneWayAndLargeCounters() {
    let uploadOnly = TrafficUsageTotals(uploadBytes: 1_024, downloadBytes: 0)
    let downloadOnly = TrafficUsageTotals(uploadBytes: 0, downloadBytes: 1_024)
    #expect(uploadOnly.uploadFraction == 1)
    #expect(uploadOnly.downloadFraction == 0)
    #expect(downloadOnly.uploadFraction == 0)
    #expect(downloadOnly.downloadFraction == 1)

    let large = TrafficUsageTotals(uploadBytes: Int.max, downloadBytes: Int.max)
    #expect(large.uploadFraction == 0.5)
    #expect(large.downloadFraction == 0.5)
    let asymmetric = TrafficUsageTotals(uploadBytes: Int.max, downloadBytes: 1)
    #expect((asymmetric.downloadFraction ?? 0) > 0)
}

@MainActor
@Test func trafficUsagePercentagesFollowConnectionsTotalsAcrossUpdatesAndUnits() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suiteName = "TrafficUsageTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
    let store = AppStore(
        profileRepository: ManagedProfileRepository(rootURL: root),
        userDefaults: defaults
    )

    store.applyConnectionsResponse(Data("""
    {"uploadTotal":19300,"downloadTotal":41600,"connections":[]}
    """.utf8))
    let original = try #require(store.trafficUsageTotals.uploadFraction)
    #expect(abs(original - 0.3169129720853859) < 0.000_000_001)

    // Different display units must not distort the share calculated from raw bytes.
    store.applyConnectionsResponse(Data("""
    {"uploadTotal":512,"downloadTotal":1048576,"connections":[]}
    """.utf8))
    #expect(store.uploadTrafficUnit == "B")
    #expect(store.downloadTrafficUnit == "MB")
    let updated = try #require(store.trafficUsageTotals.uploadFraction)
    #expect(updated < 0.001)
    #expect(updated != original)

    let confirmedTotals = store.trafficUsageTotals
    store.applyTrafficResponse(Data(#"{"up":1000000,"down":0}"#.utf8))
    #expect(store.trafficUsageTotals == confirmedTotals)
    store.applyConnectionsResponse(Data("invalid".utf8))
    #expect(store.trafficUsageTotals == confirmedTotals)

    store.applyConnectionsResponse(Data("""
    {"uploadTotal":0,"downloadTotal":0,"connections":[]}
    """.utf8))
    #expect(store.trafficUsageTotals == .zero)
    #expect(store.uploadTotalText == "0")
    #expect(store.downloadTotalText == "0")
}
