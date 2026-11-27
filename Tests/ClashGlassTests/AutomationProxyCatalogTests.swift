import Foundation
import Testing
@testable import ClashGlassCore

@Test func automationNodeIdentityDistinguishesProfilesSelectorsAndAmbiguousSeparators() throws {
    let first = AutomationProxyNode(profileID: "profile-a", groupName: "Routes/Asia", name: "Tokyo")
    let sameSpokenName = AutomationProxyNode(profileID: "profile-b", groupName: "Routes/Asia", name: "Tokyo")
    let differentSelector = AutomationProxyNode(profileID: "profile-a", groupName: "Routes", name: "Tokyo")
    let ambiguousSeparator = AutomationProxyNode(profileID: "profile-a", groupName: "Routes", name: "Asia/Tokyo")
    let identities = [first, sameSpokenName, differentSelector, ambiguousSeparator].map(\.id)

    #expect(Set(identities).count == identities.count)
    #expect(identities.allSatisfy { !$0.isEmpty })

    // Siri stores entity identifiers across app launches. Persistence must retain
    // the exact identity, including non-ASCII and user-controlled separators.
    let unicode = AutomationProxyNode(profileID: "profile-a", groupName: "主要/线路", name: "香港 🇭🇰 01")
    let restored = try JSONDecoder().decode(AutomationProxyNode.self, from: JSONEncoder().encode(unicode))
    #expect(restored.id == unicode.id)
    #expect(restored == unicode)
}
