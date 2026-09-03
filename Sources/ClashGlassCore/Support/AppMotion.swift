import SwiftUI

public enum AppMotionPolicy {
    public static func reducesMotion(
        systemPreference: Bool,
        appPreference: Bool
    ) -> Bool {
        systemPreference || appPreference
    }
}

private struct ClashGlassReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var clashGlassReduceMotion: Bool {
        get { self[ClashGlassReduceMotionKey.self] }
        set { self[ClashGlassReduceMotionKey.self] = newValue }
    }
}
