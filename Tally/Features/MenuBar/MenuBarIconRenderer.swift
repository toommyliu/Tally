import AppKit

enum MenuBarIconRenderer {
    static let statusItemLength: CGFloat = 30

    static func image(count: Int) -> NSImage? {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.cacheMode = .never

        image.lockFocus()
        defer { image.unlockFocus() }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let symbol = NSImage(
            systemSymbolName: "checklist",
            accessibilityDescription: "Tally"
        )?.withSymbolConfiguration(symbolConfiguration)
        let symbolRect = NSRect(
            x: 2,
            y: 1,
            width: 16,
            height: 16
        )
        NSGraphicsContext.current?.imageInterpolation = .high
        symbol?.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.labelColor.setFill()
        symbolRect.fill(using: .sourceAtop)

        if count > 0 {
            let text = count > 99 ? "99+" : "\(count)"
            let badgeWidth: CGFloat = text == "99+" ? 16 : 13
            let badgeRect = NSRect(x: size.width - badgeWidth - 1.5, y: 7, width: badgeWidth, height: 11)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 5.5, yRadius: 5.5)
            NSColor.labelColor.withAlphaComponent(0.92).setFill()
            badgePath.fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                .foregroundColor: NSColor.windowBackgroundColor
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedText.size()
            attributedText.draw(at: NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            ))
        }

        return image
    }
}
