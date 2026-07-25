import AppKit
import SwiftUI

enum TallyChrome {
    static let quickAddPanelSize = CGSize(width: 590, height: 190)
    static let quickAddFooterHeight: CGFloat = 56
    static let panelCornerRadius: CGFloat = 14
}

enum TallyPalette {
    static var accent: Color { Color(nsColor: .controlAccentColor) }
    static let date = Color(nsColor: .systemBlue)
    static let list = Color(nsColor: .systemIndigo)
    static let tag = Color(nsColor: .systemTeal)
    static let priority = Color(nsColor: .systemOrange)
}

struct TallyPanelBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

#if canImport(AppKit)
extension NSHostingController {
    static func tallyClearBackground(rootView: Content) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: rootView)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        return controller
    }
}

extension NSView {
    func prepareForTallyTransparentWindow() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        subviews.forEach { $0.prepareForTallyTransparentWindow() }
    }
}
#endif
