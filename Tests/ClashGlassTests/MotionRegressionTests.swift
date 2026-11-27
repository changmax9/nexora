import Testing
@testable import ClashGlassCore

@Test func toolbarActionIdentitySurvivesProgressAndLanguageChanges() {
    let idle = FeatureAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}
    let busy = FeatureAction(id: "refresh", title: "12 / 40", symbol: "hourglass", isDisabled: true) {}
    let localized = FeatureAction(id: "refresh", title: "刷新", symbol: "arrow.clockwise") {}
    let settings = FeatureAction(id: "settings", title: "Settings", symbol: "slider.horizontal.3") {}

    // SwiftUI must update the existing button instead of replacing it mid press/hover.
    #expect(idle.id == busy.id)
    #expect(idle.id == localized.id)
    #expect(idle.id != settings.id)
}
