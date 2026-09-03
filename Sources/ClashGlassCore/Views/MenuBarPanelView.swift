import SwiftUI

public struct MenuBarPanelView: View {
    @Bindable private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        let accent = store.accent.color(for: colorScheme)
        let palette = GlassPalette(colorScheme: colorScheme, accent: accent)
        VStack(alignment: .leading, spacing: MenuBarQuickAccessPolicy.sectionSpacing) {
            header(palette: palette)
            mainControlSection
            nodeSection(palette: palette)
        }
        .padding(MenuBarQuickAccessPolicy.outerPadding)
        .frame(
            width: MenuBarQuickAccessPolicy.panelWidth,
            height: MenuBarQuickAccessPolicy.panelHeight,
            alignment: .top
        )
        .background(palette.background.opacity(0.88))
        .clipped()
        .tint(accent)
        .accentColor(accent)
        .environment(
            \.clashGlassReduceMotion,
            AppMotionPolicy.reducesMotion(
                systemPreference: accessibilityReduceMotion,
                appPreference: store.reduceMotion
            )
        )
        .task {
            if !store.isCoreRunning {
                await store.refreshProxies()
            }
            await store.refreshNetworkIdentity()
        }
    }

    private func header(palette: GlassPalette) -> some View {
        let serverName = store.menuBarHeaderTitle
        return MenuBarPanelSurface(radius: 18, padding: 12) {
            HStack(spacing: 12) {
                Text(NetworkIdentity(
                    ip: "",
                    countryCode: store.networkCountryCode,
                    countryName: ""
                ).flagEmoji)
                .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 3) {
                    Text(serverName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                        .help(serverName)
                    Text(store.externalIP)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if store.isLatencyTesting {
                    ProgressView(value: store.latencyTestProgress.fraction)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    LiquidIconButton(
                        title: store.text(.refresh),
                        symbol: "arrow.clockwise",
                        size: 30
                    ) {
                        Task {
                            await store.refreshProxiesAndLatency()
                            await store.refreshNetworkIdentity()
                        }
                    }
                }
            }
        }
        .frame(height: MenuBarQuickAccessPolicy.headerHeight)
    }

    private var mainControlSection: some View {
        MenuBarPanelSurface(radius: 18, padding: 12) {
            MenuBarToggleRow(
                title: "VPN",
                detail: mainVPNDetail,
                symbol: "shield.lefthalf.filled",
                isOn: store.isStarted
            ) {
                Task {
                    await store.toggleRuntime(configPath: store.configPath)
                }
            }
        }
        .frame(height: MenuBarQuickAccessPolicy.mainControlHeight)
    }

    private var mainVPNDetail: String {
        guard store.isStarted else {
            return store.text(.stopped)
        }
        return store.isSystemProxyEnabled ? store.text(.connected) : store.text(.coreRunning)
    }

    private func nodeSection(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.menuBarProfileTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text("\(store.menuBarProxyNodes.count) \(store.text(.nodes))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }
            .padding(.horizontal, 4)
            .frame(height: MenuBarQuickAccessPolicy.nodeHeaderHeight)

            MenuBarPanelSurface(radius: 18, padding: 6) {
                if store.menuBarProxyNodes.isEmpty {
                    Text(store.text(.noProxyNodes))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 3) {
                            ForEach(store.menuBarProxyNodes) { node in
                                MenuBarProxyRow(node: node) {
                                    Task {
                                        await store.selectProxyRemote(
                                            groupName: MenuBarQuickAccessPolicy.selectorName,
                                            nodeName: node.name
                                        )
                                    }
                                }
                            }
                        }
                        .padding(2)
                    }
                    .scrollIndicators(.visible)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(height: MenuBarQuickAccessPolicy.nodeViewportHeight)
        }
        .frame(
            height: MenuBarQuickAccessPolicy.nodeHeaderHeight
                + MenuBarQuickAccessPolicy.nodeHeaderSpacing
                + MenuBarQuickAccessPolicy.nodeViewportHeight
        )
    }

}

private struct MenuBarPanelSurface<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        radius: CGFloat,
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                palette.cardFill,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .modifier(MenuBarGlassModifier(radius: radius))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 1.2)
            }
    }
}

private struct MenuBarGlassModifier: ViewModifier {
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: .rect(cornerRadius: radius))
        } else {
            content
        }
    }
}

private struct MenuBarToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }

            Spacer()

            LiquidToggle(isOn: isOn, action: action)
                .frame(width: 52, height: 40)
        }
    }
}

private struct MenuBarProxyRow: View {
    let node: ProxyNode
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.rose)
                    .frame(width: 14)
                    .opacity(node.isSelected ? 1 : 0)
                    .accessibilityHidden(!node.isSelected)

                Text(node.name)
                    .font(.system(size: 12, weight: node.isSelected ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text(node.latency.map { "\($0) ms" } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(latencyColor(palette: palette))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                node.isSelected
                    ? palette.selectionFill
                    : isHovering ? palette.selectionHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if node.isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.selectionStroke, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(node.name)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78),
            value: isHovering
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.80),
            value: node.isSelected
        )
    }

    private func latencyColor(palette: GlassPalette) -> Color {
        guard let latency = node.latency else {
            return palette.tertiaryText
        }
        return latency < 180 ? palette.green : .orange
    }
}
