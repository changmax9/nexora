import AppKit

@MainActor
enum NexoraStatusIcon {
    // The two folded ends and central hub from Assets/AppIcon.png, drawn as a
    // vector template so macOS can tint the mark on light and dark menu bars.
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()

            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: 1.79 + (x - 205) * 16 / 680, y: 1 + (y - 170) * 16 / 680)
            }

            let connection = NSBezierPath()
            connection.move(to: point(398, 351))
            connection.line(to: point(425, 333))
            connection.line(to: point(627, 668))
            connection.line(to: point(600, 687))
            connection.close()
            connection.fill()

            let hub = NSBezierPath(ovalIn: NSRect(
                x: point(426, 424).x, y: point(426, 424).y,
                width: 171 * 16 / 680, height: 171 * 16 / 680
            ))
            hub.fill()

            let upper = NSBezierPath()
            upper.move(to: point(414, 170))
            upper.line(to: point(584, 170))
            upper.curve(to: point(604, 224), controlPoint1: point(613, 170), controlPoint2: point(624, 197))
            upper.line(to: point(535, 312))
            upper.curve(to: point(514, 327), controlPoint1: point(529, 321), controlPoint2: point(524, 327))
            upper.line(to: point(435, 327))
            upper.curve(to: point(416, 337), controlPoint1: point(426, 327), controlPoint2: point(422, 330))
            upper.line(to: point(366, 397))
            upper.line(to: point(366, 507))
            upper.curve(to: point(343, 530), controlPoint1: point(366, 523), controlPoint2: point(360, 530))
            upper.line(to: point(303, 530))
            upper.curve(to: point(278, 517), controlPoint1: point(292, 530), controlPoint2: point(284, 524))
            upper.line(to: point(214, 420))
            upper.curve(to: point(218, 359), controlPoint1: point(200, 400), controlPoint2: point(202, 378))
            upper.line(to: point(378, 188))
            upper.curve(to: point(414, 170), controlPoint1: point(389, 176), controlPoint2: point(400, 170))
            upper.close()
            upper.fill()

            // The lower end has the same silhouette, rotated around the hub.
            let lower = upper.copy() as! NSBezierPath
            let rotation = AffineTransform(
                m11: -1, m12: 0, m21: 0, m22: -1,
                tX: 18, tY: 18
            )
            lower.transform(using: rotation)
            lower.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nexora"
        return image
    }
}
