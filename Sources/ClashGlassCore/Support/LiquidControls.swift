import AppKit
import SwiftUI

public enum LiquidControlMotion {
    public static func scale(isHovering: Bool, isPressed: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion else {
            return 1
        }
        if isPressed {
            return 0.975
        }
        return isHovering ? 1.025 : 1
    }
}

public enum LiquidControlInteractionPolicy {
    public static let usesNativeButtonPressState = true
    public static let usesSupplementalDragGesture = false
    public static let nestsInteractiveGlassInsideButton = false
    public static let usesNativeButtonAction = true
    public static let triggersActionOnPressDown = false
    public static let minimumHitTarget: Double = 40
}

public enum ToolbarControlMetrics {
    public static let visibleSize: Double = 34
    public static let hitTarget = LiquidControlInteractionPolicy.minimumHitTarget
}

public enum ToolbarControlAppearancePolicy {
    public static let runningCoreSymbol = "checkmark"
    public static let stoppedCoreSymbol = "arrow.clockwise"
    public static let runningCoreUsesSolidGreenSurface = false
    public static let runningCoreUsesWhiteSymbol = false
    public static let quickEditUsesNativeMenu = true
    public static let quickEditUsesPlainIcon = false
    public static let quickEditUsesCompactGlassSurface = true
    public static let quickEditKeepsSurfaceOutsideNativeMenuLabel = true
    public static let quickEditVisualSurfaceAllowsHitTesting = false
    public static let quickEditHitLayerUsesVisibleAlpha = false
    public static let quickEditUsesSingleInteractiveSurface = true
    public static let quickEditUsesAppKitMenuBridge = true
    public static let quickEditSymbol = "pencil"
    public static let controlCornerRadius: Double = 11
}

public enum SelectionControlMotion {
    public static let labelScale: Double = 1

    public static func indicatorScale(
        isHovering: Bool,
        isPressed: Bool,
        reduceMotion: Bool
    ) -> Double {
        guard !reduceMotion else {
            return 1
        }
        if isPressed {
            return 0.92
        }
        return isHovering ? 1.08 : 1
    }
}

public enum ModeRowInteractionPolicy {
    public static let usesFullRowHitTarget = true
    public static let animatesIndicatorOnly = true
    public static let usesNativeButtonAction = true
    public static let triggersActionOnPressDown = false
    public static let minimumHitHeight: Double = 40
}

struct LiquidGlassButtonStyle: ButtonStyle {
    var radius: CGFloat = 12
    var tint: Color?
    var hoverScale = 1.025
    var pressedScale = 0.975

    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            radius: radius,
            tint: tint,
            hoverScale: hoverScale,
            pressedScale: pressedScale
        )
    }
}

private struct LiquidIconButtonStyle: ButtonStyle {
    let visibleSize: CGFloat
    let hitTarget: CGFloat
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Color.clear
                .frame(width: hitTarget, height: hitTarget)

            LiquidGlassButtonBody(
                label: configuration.label
                    .frame(width: visibleSize, height: visibleSize),
                isPressed: configuration.isPressed,
                radius: visibleSize * 0.34,
                tint: tint,
                hoverScale: 1.025,
                pressedScale: 0.94
            )
            .frame(width: visibleSize, height: visibleSize)
        }
        .contentShape(Rectangle())
    }
}

struct CoreStatusToolbarButton: View {
    let symbol: String
    let isRunning: Bool
    let accessibilityTitle: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let runningSurface = Color(
            red: 139.0 / 255.0,
            green: 249.0 / 255.0,
            blue: 212.0 / 255.0
        )
        let referenceInk = Color(
            red: 31.0 / 255.0,
            green: 25.0 / 255.0,
            blue: 29.0 / 255.0
        )
        Button(action: action) {
            ZStack {
                Color.clear
                    .frame(
                        width: CGFloat(ToolbarControlMetrics.hitTarget),
                        height: CGFloat(ToolbarControlMetrics.hitTarget)
                    )

                RoundedRectangle(
                    cornerRadius: CGFloat(
                        ToolbarControlAppearancePolicy.controlCornerRadius
                    ),
                    style: .continuous
                )
                .fill(
                    isRunning
                        ? runningSurface
                        : palette.cardFill
                )
                .frame(
                    width: CGFloat(ToolbarControlMetrics.visibleSize),
                    height: CGFloat(ToolbarControlMetrics.visibleSize)
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CGFloat(
                            ToolbarControlAppearancePolicy.controlCornerRadius
                        ),
                        style: .continuous
                    )
                    .strokeBorder(
                        isRunning
                            ? Color.white.opacity(0.32)
                            : palette.cardStroke,
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: isRunning
                        ? runningSurface.opacity(isHovering ? 0.28 : 0.14)
                        : .clear,
                    radius: 8,
                    y: 3
                )

                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        isRunning ? referenceInk : palette.secondaryText
                    )
            }
            .frame(
                width: CGFloat(ToolbarControlMetrics.hitTarget),
                height: CGFloat(ToolbarControlMetrics.hitTarget),
                alignment: .center
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72),
            value: isHovering
        )
        .help(accessibilityTitle)
        .accessibilityLabel(accessibilityTitle)
    }
}

struct ToolbarMenuIconSurface: View {
    let symbol: String
    var size: CGFloat = CGFloat(ToolbarControlMetrics.visibleSize)
    var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let referenceSurface = colorScheme == .dark
            ? Color.white
            : Color.black
        let referenceInk = colorScheme == .dark ? Color.black : Color.white
        ZStack {
            Color.clear
                .frame(
                    width: CGFloat(ToolbarControlMetrics.hitTarget),
                    height: CGFloat(ToolbarControlMetrics.hitTarget)
                )

            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundStyle(referenceInk)
                .frame(width: size, height: size)
                .background(
                    referenceSurface,
                    in: RoundedRectangle(
                        cornerRadius: CGFloat(
                            ToolbarControlAppearancePolicy.controlCornerRadius
                        ),
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CGFloat(
                            ToolbarControlAppearancePolicy.controlCornerRadius
                        ),
                        style: .continuous
                    )
                        .strokeBorder(
                            isHovering
                                ? palette.selectionStroke.opacity(0.72)
                                : Color.black.opacity(0.05),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(isHovering ? 0.12 : 0.07),
                    radius: isHovering ? 9 : 6,
                    y: 3
                )
                .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)
        }
        .frame(
            width: CGFloat(ToolbarControlMetrics.hitTarget),
            height: CGFloat(ToolbarControlMetrics.hitTarget),
            alignment: .center
        )
        .contentShape(Rectangle())
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72),
            value: isHovering
        )
    }
}

@MainActor
struct AppKitMenuButton: NSViewRepresentable {
    struct Entry {
        let title: String?
        let symbol: String?
        let isEnabled: Bool
        let action: (() -> Void)?

        static func item(
            _ title: String,
            symbol: String,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) -> Entry {
            Entry(
                title: title,
                symbol: symbol,
                isEnabled: isEnabled,
                action: action
            )
        }

        static var separator: Entry {
            Entry(
                title: nil,
                symbol: nil,
                isEnabled: false,
                action: nil
            )
        }
    }

    let entries: [Entry]
    var accessibilityTitle = "Quick Edit"

    func makeCoordinator() -> Coordinator {
        Coordinator(entries: entries)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = ""
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.sendAction(on: [.leftMouseDown])
        button.setAccessibilityLabel(accessibilityTitle)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.entries = entries
        button.setAccessibilityLabel(accessibilityTitle)
    }

    @MainActor
    final class Coordinator: NSObject {
        var entries: [Entry]

        init(entries: [Entry]) {
            self.entries = entries
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false

            for (index, entry) in entries.enumerated() {
                guard let title = entry.title else {
                    menu.addItem(.separator())
                    continue
                }

                let item = NSMenuItem(
                    title: title,
                    action: #selector(performMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.isEnabled = entry.isEnabled
                if let symbol = entry.symbol {
                    item.image = NSImage(
                        systemSymbolName: symbol,
                        accessibilityDescription: title
                    )
                }
                menu.addItem(item)
            }

            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: sender)
            } else {
                menu.popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: sender.bounds.minY),
                    in: sender
                )
            }
        }

        @objc func performMenuItem(_ sender: NSMenuItem) {
            guard entries.indices.contains(sender.tag) else {
                return
            }
            entries[sender.tag].action?()
        }
    }
}

private struct LiquidGlassButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let radius: CGFloat
    let tint: Color?
    let hoverScale: Double
    let pressedScale: Double
    @State private var isHovering = false
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    label
                        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
                }
            } else {
                label
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.09),
                                lineWidth: 1
                            )
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .scaleEffect(LiquidControlMotion.scale(
            isHovering: isHovering,
            isPressed: isPressed,
            reduceMotion: reduceMotion
        ) == 1 ? 1 : isPressed ? pressedScale : hoverScale)
        .offset(y: isHovering && !isPressed && !reduceMotion ? -1.5 : 0)
        .brightness(isHovering ? 0.025 : 0)
        .shadow(
            color: .black.opacity(isHovering && !reduceMotion ? 0.12 : 0),
            radius: 10,
            y: 5
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72),
            value: isHovering
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.68),
            value: isPressed
        )
        .onHover { isHovering = $0 }
    }
}

struct LiquidIconButton: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .bold))
        }
        .buttonStyle(LiquidIconButtonStyle(
            visibleSize: size,
            hitTarget: max(size, CGFloat(LiquidControlInteractionPolicy.minimumHitTarget)),
            tint: tint
        ))
        .help(title)
        .accessibilityLabel(title)
    }
}

struct LiquidActionButton: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: compact ? 11 : 13, weight: .bold, design: .rounded))
                .padding(.horizontal, compact ? 10 : 14)
                .frame(height: compact ? 28 : 34)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(LiquidGlassButtonStyle(radius: compact ? 10 : 12, tint: tint))
        .accessibilityLabel(title)
    }
}

struct LiquidToggle: View {
    let isOn: Bool
    var tint: Color? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let activeTint = tint ?? palette.green
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? activeTint.opacity(0.80) : palette.tertiaryText.opacity(0.20))
                    .frame(width: 52, height: 32)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isHovering ? activeTint.opacity(0.62) : Color.primary.opacity(0.08),
                                lineWidth: isHovering ? 1.4 : 1
                            )
                    }
                Circle()
                    .fill(isOn ? palette.primaryText : palette.tertiaryText)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 4)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .scaleEffect(isHovering && !reduceMotion ? 1.08 : 1)
                    .rotation3DEffect(
                        .degrees(isHovering && !reduceMotion ? (isOn ? 8 : -8) : 0),
                        axis: (x: 0, y: 1, z: 0)
                    )
            }
            .frame(width: 52, height: 32)
        }
        .buttonStyle(LiquidGlassButtonStyle(
            radius: 16,
            tint: isOn ? activeTint.opacity(0.25) : nil,
            hoverScale: 1.05,
            pressedScale: 0.94
        ))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.64),
            value: isHovering
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.70),
            value: isOn
        )
        .frame(
            width: 52,
            height: CGFloat(LiquidControlInteractionPolicy.minimumHitTarget)
        )
    }
}
