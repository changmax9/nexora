import SwiftUI

enum GlassCardMotion {
    static func scale(isHovering: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion else {
            return 1
        }
        return isHovering ? 1.004 : 1
    }

    static func verticalOffset(isHovering: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion else {
            return 0
        }
        return isHovering ? -1 : 0
    }

    static func shadowOpacity(isHovering: Bool, reduceMotion: Bool) -> Double {
        guard isHovering else {
            return 0
        }
        return reduceMotion ? 0.08 : 0.12
    }
}

enum GlassCardVisualMetrics {
    static let usesStableGlassMaterial = true
    static let clipsContentToRoundedShape = true
    static let shadowRadius: CGFloat = 12
    static let shadowVerticalOffset: CGFloat = 4
    static let overflowAllowance = shadowRadius + abs(shadowVerticalOffset)
    static let minimumPageInset = overflowAllowance + 12
}

struct GlassPalette {
    let colorScheme: ColorScheme
    let accent: Color

    init(colorScheme: ColorScheme, accent: Color = .accentColor) {
        self.colorScheme = colorScheme
        self.accent = accent
    }

    var background: Color {
        colorScheme == .dark ? .black : .white
    }

    var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.035)
    }

    var cardStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.14)
    }

    var primaryText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.94)
    }

    var secondaryText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.70)
            : Color.black.opacity(0.68)
    }

    var tertiaryText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.46)
            : Color.black.opacity(0.48)
    }

    var rose: Color {
        accent
    }

    var brown: Color {
        accent
    }

    var railSelection: Color {
        rose.opacity(colorScheme == .dark ? 0.22 : 0.16)
    }

    var selectionTrack: Color {
        rose.opacity(colorScheme == .dark ? 0.08 : 0.07)
    }

    var selectionFill: Color {
        rose.opacity(colorScheme == .dark ? 0.26 : 0.18)
    }

    var selectionHover: Color {
        rose.opacity(colorScheme == .dark ? 0.12 : 0.10)
    }

    var selectionStroke: Color {
        rose.opacity(colorScheme == .dark ? 0.46 : 0.40)
    }

    var green: Color {
        Color(red: 0.39, green: 0.91, blue: 0.65)
    }

    var shadow: Color {
        colorScheme == .dark
            ? Color.clear
            : Color.black.opacity(0.14)
    }
}

struct LiquidGlassSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(radius: CGFloat = 22, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Group {
            if #available(macOS 26.0, *) {
                content
                    .padding(padding)
                    .background(
                        palette.cardFill,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                    )
                    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: radius))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(palette.cardStroke, lineWidth: 0.8)
                    }
            } else {
                content
                    .padding(padding)
                    .background(palette.cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(palette.cardStroke, lineWidth: 0.8)
                    }
                    .shadow(color: palette.shadow.opacity(0.20), radius: 14, y: 6)
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false
    let radius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(radius: CGFloat = 26, padding: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Group {
            if #available(macOS 26.0, *) {
                content
                    .padding(padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        palette.cardFill,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                    )
                    .glassEffect(
                        .clear.interactive(),
                        in: .rect(cornerRadius: radius)
                    )
            } else {
                content
                    .padding(padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        palette.cardFill,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    isHovering ? palette.selectionStroke.opacity(0.82) : palette.cardStroke,
                    lineWidth: isHovering ? 1.25 : 0.9
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .scaleEffect(GlassCardMotion.scale(isHovering: isHovering, reduceMotion: reduceMotion))
        .offset(y: GlassCardMotion.verticalOffset(isHovering: isHovering, reduceMotion: reduceMotion))
        .brightness(isHovering ? 0.018 : 0)
        .shadow(
            color: palette.shadow.opacity(
                GlassCardMotion.shadowOpacity(isHovering: isHovering, reduceMotion: reduceMotion)
            ),
            radius: GlassCardVisualMetrics.shadowRadius,
            y: GlassCardVisualMetrics.shadowVerticalOffset
        )
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.74),
            value: isHovering
        )
    }
}
