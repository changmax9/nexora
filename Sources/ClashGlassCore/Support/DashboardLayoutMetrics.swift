import Foundation

public struct DashboardRowMetrics: Sendable {
    public static let standardTotalHeight: Double = 184

    public let totalHeight: Double
    public let gap: Double

    public init(totalHeight: Double, gap: Double) {
        self.totalHeight = totalHeight
        self.gap = gap
    }

    public var upperHeight: Double {
        max(0, (totalHeight - gap) / 2)
    }

    public var lowerHeight: Double {
        upperHeight
    }
}

public enum DashboardTopRowLayoutMetrics {
    public static let gap = 16.0
    public static let networkSpeedHeight = DashboardRowMetrics.standardTotalHeight
    public static let toggleCardHeight = DashboardRowMetrics(
        totalHeight: networkSpeedHeight,
        gap: gap
    ).upperHeight
}

public enum OutboundModeLayoutMetrics {
    public static let cardHeight = DashboardRowMetrics.standardTotalHeight
    public static let cardPadding: Double = 14
    public static let headerHeight: Double = 18
    public static let titleSpacing: Double = 8
    public static let rowHeight = ModeRowInteractionPolicy.minimumHitHeight
    public static let rowSpacing: Double = 3
    public static let rowCount = Double(OutboundMode.allCases.count)

    public static var requiredContentHeight: Double {
        (cardPadding * 2)
            + headerHeight
            + titleSpacing
            + (rowHeight * rowCount)
            + (rowSpacing * (rowCount - 1))
    }

    public static let minimumHeight = requiredContentHeight
}

public struct DashboardLayoutMetrics: Sendable {
    public static let baseWidth: Double = 1_256
    public static let baseHeight: Double = 722

    public let availableWidth: Double
    public let availableHeight: Double
    public let scale: Double

    public init(availableWidth: Double, availableHeight: Double) {
        self.availableWidth = max(availableWidth, 1)
        self.availableHeight = max(availableHeight, 1)
        scale = min(1, self.availableWidth / Self.baseWidth, self.availableHeight / Self.baseHeight)
    }

    public var renderedWidth: Double {
        Self.baseWidth * scale
    }

    public var renderedHeight: Double {
        Self.baseHeight * scale
    }
}
