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
    static let appliesToExternalSectionChanges = true
    static let usesMatchedGeometry = true
    static let respectsReducedMotion = true

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .spring(response: 0.42, dampingFraction: 0.80)
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
    let showsSelectionBackground: Bool
    let showsHoverBackground: Bool
    let isHovered: Bool
    let scale: Double
    let iconScale: Double
    let horizontalOffset: Double
    let verticalOffset: Double
    let brightness: Double
    let shadowOpacity: Double
    let selectionGlowOpacity: Double

    init(
        item: RailItem,
        selectedSection: AppSection,
        hoveredItem: RailItem?,
        reduceMotion: Bool
    ) {
        let isSelected = item == RailSelectionResolver.item(for: selectedSection)
        showsSelectionBackground = isSelected
        isHovered = hoveredItem == item
        showsHoverBackground = isHovered && !isSelected

        scale = 1
        if reduceMotion {
            iconScale = 1
            horizontalOffset = 0
        } else if isHovered {
            iconScale = 1.035
            horizontalOffset = 0
        } else if isSelected {
            iconScale = 1
            horizontalOffset = 0
        } else {
            iconScale = 1
            horizontalOffset = 0
        }
        verticalOffset = 0
        brightness = isHovered ? 0.012 : 0
        shadowOpacity = 0
        selectionGlowOpacity = isHovered ? 0.08 : isSelected ? 0.075 : 0
    }
}
