import Foundation

public enum MenuBarPanelPlacement {
    public static func origin(panelSize: CGSize, statusFrame: CGRect, visibleFrame: CGRect) -> CGPoint {
        let inset: CGFloat = 8
        let minX = visibleFrame.minX + inset
        let minY = visibleFrame.minY + inset
        let maxX = max(minX, visibleFrame.maxX - panelSize.width - inset)
        let maxY = max(minY, visibleFrame.maxY - panelSize.height)
        return CGPoint(
            x: min(max(statusFrame.midX - panelSize.width / 2, minX), maxX),
            y: min(max(statusFrame.minY - panelSize.height - 6, minY), maxY)
        )
    }
}
