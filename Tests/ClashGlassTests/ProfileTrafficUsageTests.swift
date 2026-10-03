import Foundation
import Testing
@testable import ClashGlassCore

@Test func profileTrafficUsageCountsBothDirectionsAndShowsRemainingQuota() throws {
    let usage = try #require(ProfileTrafficUsage(
        subscriptionUserInfo: "Upload=5368709120; download=21474836480; total=107374182400; expire=1800000000"
    ))
    #expect(usage.remainingBytes == 80_530_636_800)
    #expect(usage.remainingGigabytes == 75)
    #expect(usage.remainingFraction == 0.75)
}

@Test func profileTrafficUsageRejectsIncompleteOrInvalidProviderCounters() {
    for header in [nil, "", "upload=0; download=0", "upload=-1; download=0; total=100",
                   "upload=nan; download=0; total=100", "upload=0; download=0; total=9223372036854775808",
                   "upload=0; upload=1; download=0; total=100"] as [String?] {
        #expect(ProfileTrafficUsage(subscriptionUserInfo: header) == nil)
    }
    let unspecifiedQuota = ProfileTrafficUsage(subscriptionUserInfo: "upload=0; download=0; total=0")
    #expect(unspecifiedQuota?.remainingBytes == nil)
    #expect(unspecifiedQuota?.remainingFraction == nil)
}

@Test func profileTrafficUsageClampsExhaustedAndHugeCountersWithoutOverflow() throws {
    let exhausted = try #require(ProfileTrafficUsage(subscriptionUserInfo: "upload=40; download=80; total=100"))
    #expect(exhausted.remainingFraction == 0)
    #expect(exhausted.remainingBytes == 0)
    let huge = try #require(ProfileTrafficUsage(
        subscriptionUserInfo: "upload=9223372036854775807; download=9223372036854775807; total=9223372036854775807"
    ))
    #expect(huge.remainingBytes == 0)
    let unused = try #require(ProfileTrafficUsage(subscriptionUserInfo: "upload=0; download=0; total=100"))
    #expect(unused.remainingFraction == 1)
}

@Test func managedProfileDecodesRegistriesCreatedBeforeTrafficMetadata() throws {
    let json = Data(#"{"id":"C9D3C01F-F4CF-4FA1-8E58-50CFAAE052AB","name":"Local","managedConfigURL":"file:///tmp/config.yaml","importedAt":"2026-10-01T00:00:00Z"}"#.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let profile = try decoder.decode(ManagedProfile.self, from: json)
    #expect(profile.name == "Local")
    #expect(profile.trafficUsage == nil)
    #expect(profile.subscriptionURL == nil)
}
