import Foundation
import SwiftUI

enum RailSurfaceMetrics {
    static let usesSystemGlassSelection = false
    static let backgroundMatchesWindow = true
    static let railZIndex = 1.0
    static let stageZIndex = 0.0
    static let selectionShadowRadius = 8.0
    static let selectionTrailingClearance = 10.0
}

enum RailHitTargetMetrics {
    static let width = 74.0
    static let height = 48.0
}

enum RailLayoutMetrics {
    static let itemSpacing = 4.0
    static let topInset = 46.0
    static let selectionWidth = 54.0
    static let selectionHeight = 30.0

    static func selectionOffset(for section: AppSection) -> Double {
        let index = AppSection.allCases.firstIndex(of: section) ?? 0
        return Double(index) * (RailHitTargetMetrics.height + itemSpacing)
    }
}

enum RailItem: Equatable {
    case section(AppSection)
}

enum RailSelectionResolver {
    static func item(for section: AppSection) -> RailItem {
        switch section {
        case .dashboard:
            .section(.dashboard)
        case .diagnostics:
            .section(.diagnostics)
        case .proxies:
            .section(.proxies)
        case .routing:
            .section(.routing)
        case .profiles:
            .section(.profiles)
        case .connections:
            .section(.connections)
        case .settings:
            .section(.settings)
        }
    }
}

enum RailSelectionMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        PageNavigationTransitionPolicy.animation(reduceMotion: reduceMotion)
    }
}

struct RailHoverState {
    private(set) var hoveredItem: RailItem?

    mutating func update(item: RailItem, isHovering: Bool) {
        if isHovering {
            hoveredItem = item
        } else if hoveredItem == item {
            hoveredItem = nil
        }
    }
}

struct RailItemPresentation {
    let isSelected: Bool
    let isHovered: Bool

    var emphasizesIcon: Bool { isSelected || isHovered }

    init(
        item: RailItem,
        selectedSection: AppSection,
        hoveredItem: RailItem?
    ) {
        isSelected = item == RailSelectionResolver.item(for: selectedSection)
        isHovered = hoveredItem == item
    }
}
