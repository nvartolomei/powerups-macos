import Cocoa

/// The status item's art: the app's bolt, with a coffee cup badged into the corner while sleep is being prevented.
class MenubarIcon {
    private static let canvas = CGFloat(22)
    private static let boltPoints = [(13.6, 3.5), (6.6, 11.6), (10.4, 11.6), (8.4, 18.5), (15.4, 10.4), (11.6, 10.4)]
    private static let boltOrigin = CGPoint(x: 6.6, y: 3.5)
    /// the bolt shrinks into the top-left corner to clear the badge, rather than the two of them overlapping
    private static let badgedBolt = (scale: CGFloat(0.8), origin: CGPoint(x: 1, y: 1))
    private static let badgeBox = NSRect(x: 11, y: 11.5, width: 10.5, height: 10.5)
    /// a mug, not a cup and saucer: at 22 points the saucer dissolves into a dash under a blob
    private static let cupSymbolName = "mug.fill"

    /// there are only ever two of these, and the menu asks for one every time it opens
    private static let plain = draw(false)
    private static let badged = draw(true)

    static func image(_ active: Bool) -> NSImage {
        active ? badged : plain
    }

    private static func draw(_ active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
            NSColor.black.setFill()
            boltPath(active).fill()
            if active {
                drawBadge()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func boltPath(_ badged: Bool) -> NSBezierPath {
        let scale = badged ? badgedBolt.scale : 1
        let origin = badged ? badgedBolt.origin : boltOrigin
        let points = boltPoints.map {
            NSPoint(x: ($0.0 - boltOrigin.x) * scale + origin.x, y: ($0.1 - boltOrigin.y) * scale + origin.y)
        }
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        return path
    }

    /// kept to the symbol's own proportions and anchored to the corner, so it reads as a badge and not a squashed cup
    private static func drawBadge() {
        guard let cup = NSImage(systemSymbolName: cupSymbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)) else { return }
        let scale = min(badgeBox.width / cup.size.width, badgeBox.height / cup.size.height)
        let size = NSSize(width: cup.size.width * scale, height: cup.size.height * scale)
        let rect = NSRect(x: badgeBox.maxX - size.width, y: badgeBox.maxY - size.height, width: size.width, height: size.height)
        cup.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
