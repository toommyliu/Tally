import AppKit
import SwiftUI

enum TallyChrome {
    static let quickAddWindowSize = CGSize(width: 540, height: 188)
    static let quickAddShadowPadding: CGFloat = 28
    static let quickAddPanelSize = CGSize(
        width: quickAddWindowSize.width + quickAddShadowPadding * 2,
        height: quickAddWindowSize.height + quickAddShadowPadding * 2
    )
    static let panelCornerRadius: CGFloat = 20
    static let popoverCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 8
    static let sectionCornerRadius: CGFloat = 12
}

extension View {
    func tallyChromeSurface(
        cornerRadius: CGFloat,
        material: Material = .regularMaterial,
        strokeOpacity: Double = 0.18,
        shadowOpacity: Double = 0.18,
        shadowRadius: CGFloat = 26,
        shadowY: CGFloat = 12
    ) -> some View {
        modifier(TallyChromeSurfaceModifier(
            cornerRadius: cornerRadius,
            material: material,
            strokeOpacity: strokeOpacity,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }

    func tallyInsetGlassSurface(cornerRadius: CGFloat = TallyChrome.sectionCornerRadius) -> some View {
        modifier(TallyInsetGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func tallyPrimaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func tallySecondaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

private struct TallyChromeSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let material: Material
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .background(material, in: shape)
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.stroke(strokeColor, lineWidth: 0.75)
                }
                .compositingGroup()
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        } else {
            content
                .background(material, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.stroke(strokeColor, lineWidth: 0.75)
                }
                .compositingGroup()
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        }
    }

    private var strokeColor: Color {
        if colorScheme == .dark {
            return .white.opacity(strokeOpacity)
        }

        return .black.opacity(strokeOpacity * 0.55)
    }

    private var shadowColor: Color {
        .black.opacity(colorScheme == .dark ? shadowOpacity : shadowOpacity * 0.70)
    }
}

private struct TallyInsetGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.035))
            }
            .overlay {
                shape.stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055), lineWidth: 0.75)
            }
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
