import AppKit
import SwiftUI

public struct GlassAppearance: Equatable, Sendable {
    public static let defaultBlurStrength = 1.0
    public let blurStrength: Double

    public init(blurStrength: Double = defaultBlurStrength) {
        self.blurStrength = Self.normalized(blurStrength)
    }

    public static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

private struct GlassAppearanceKey: EnvironmentKey {
    static let defaultValue = GlassAppearance()
}

public extension EnvironmentValues {
    var nexoraGlassAppearance: GlassAppearance {
        get { self[GlassAppearanceKey.self] }
        set { self[GlassAppearanceKey.self] = newValue }
    }
}

/// Changes the native backdrop material without fading the foreground.
struct WindowGlassBackground: View {
    let appearance: GlassAppearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                GlassPalette(colorScheme: colorScheme).background
            } else {
                DesktopBackdrop(blurStrength: appearance.blurStrength)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DesktopBackdrop: NSViewRepresentable {
    var blurStrength: Double

    func makeNSView(context: Context) -> NativeBackdropView {
        let view = NativeBackdropView()
        view.setBlurStrength(blurStrength)
        return view
    }

    func updateNSView(_ view: NativeBackdropView, context: Context) {
        view.setBlurStrength(blurStrength)
    }
}

private final class NativeBackdropView: NSView {
    private let lightMaterial: NSView
    private let frostedMaterial: NSView

    override init(frame frameRect: NSRect) {
        if #available(macOS 26, *) {
            let clear = NSGlassEffectView()
            clear.style = .clear
            clear.cornerRadius = 0
            let regular = NSGlassEffectView()
            regular.style = .regular
            regular.cornerRadius = 0
            lightMaterial = clear
            frostedMaterial = regular
        } else {
            let light = NSVisualEffectView()
            light.material = .sidebar
            let frosted = NSVisualEffectView()
            frosted.material = .underWindowBackground
            for view in [light, frosted] {
                view.blendingMode = .behindWindow
                view.state = .active
            }
            lightMaterial = light
            frostedMaterial = frosted
        }
        super.init(frame: frameRect)
        for view in [lightMaterial, frostedMaterial] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { nil }

    func setBlurStrength(_ strength: Double) {
        // AppKit exposes material styles, not a blur radius. Blend the native
        // frosted material over a constant glass base so low values stay glass.
        frostedMaterial.alphaValue = strength
        frostedMaterial.isHidden = strength == 0
        lightMaterial.isHidden = strength == 1
    }
}

struct TileGlassBackground: View {
    var radius: CGFloat

    var body: some View {
        Color.clear
            .modifier(TileGlassSurface(radius: radius, interactive: false))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The same material blend is shared by the window and its cards.
struct TileGlassSurface: ViewModifier {
    var radius: CGFloat
    var interactive: Bool
    @Environment(\.nexoraGlassAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityShowBorders) private var showBorders

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let palette = GlassPalette(colorScheme: colorScheme)
        Group {
            if reduceTransparency {
                content.background(palette.background, in: shape)
            } else if #available(macOS 26, *) {
                content
                    .background {
                        ZStack {
                            Color.clear
                                .glassEffect(.clear.interactive(interactive && !reduceMotion), in: shape)
                                .opacity(appearance.blurStrength == 1 ? 0 : 1)
                            Color.clear
                                .glassEffect(.regular.interactive(interactive && !reduceMotion), in: shape)
                                .opacity(appearance.blurStrength)
                        }
                    }
            } else {
                content
                    .background {
                        ZStack {
                            shape.fill(.ultraThinMaterial)
                            shape.fill(.regularMaterial).opacity(appearance.blurStrength)
                        }
                    }
            }
        }
        .overlay {
            shape.strokeBorder(
                contrast == .increased || showBorders ? Color.primary.opacity(0.65) : palette.cardStroke,
                lineWidth: contrast == .increased || showBorders ? 1.5 : 0.7
            )
        }
    }
}
