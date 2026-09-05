import SwiftUI

enum PageNavigationTransitionPolicy {
    static let animatesTitleChange = true
    static let crossfadesFeatureContent = false
    static let respectsReducedMotion = true
    static let duration = 0.20

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}
