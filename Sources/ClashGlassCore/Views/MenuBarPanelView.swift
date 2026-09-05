import SwiftUI

public struct MenuBarPanelView: View {
    @Bindable private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var searchText = ""
    @State private var isRefreshingNodes = false

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        let accent = store.accent.color(for: colorScheme)
        let palette = GlassPalette(colorScheme: colorScheme, accent: accent)
        VStack(alignment: .leading, spacing: MenuBarQuickAccessPolicy.sectionSpacing) {
            HStack(spacing: 8) {
                Text("Nexora")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 12)
                Text(store.menuBarProfileTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.menuBarProfileTitle)
            }
            .frame(height: MenuBarQuickAccessPolicy.headerHeight)

            connectionSection(palette: palette)
            nodeSection(palette: palette)
            footer(palette: palette)
        }
        .padding(MenuBarQuickAccessPolicy.outerPadding)
        .frame(width: MenuBarQuickAccessPolicy.panelWidth, height: MenuBarQuickAccessPolicy.panelHeight)
        .background(palette.background.opacity(0.97))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.cardStroke.opacity(0.6), lineWidth: 0.5)
        }
        .tint(accent)
        .accentColor(accent)
        .environment(\.clashGlassReduceMotion, AppMotionPolicy.reducesMotion(
            systemPreference: accessibilityReduceMotion, appPreference: store.reduceMotion
        ))
    }

    private var connectionTitle: String {
        if store.isRuntimeTransitioning { return store.text(.updating) }
        guard store.isStarted else { return store.text(.stopped) }
        return store.text(store.isSystemProxyEnabled || store.isTunEnabled ? .connected : .coreRunning)
    }

    private func connectionSection(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: store.isStarted ? "shield.lefthalf.filled" : "shield")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(store.isStarted ? palette.rose : palette.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(store.isStarted ? palette.selectionFill : palette.cardFill, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(connectionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("VPN · \(store.text(store.selectedMode.titleKey))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if store.isRuntimeTransitioning {
                    ProgressView().controlSize(.small)
                        .frame(width: 52, height: 36)
                } else {
                    LiquidToggle(isOn: store.isStarted) {
                        Task { await store.toggleRuntime(configPath: store.configPath) }
                    }
                    .frame(width: 52, height: 36)
                    .accessibilityLabel("VPN")
                }
            }
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.text(.menuSelectedNode))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(store.menuBarSelectedNodeName ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.menuBarSelectedNodeName ?? "")
            }
            HStack(spacing: 5) {
                Text(NetworkIdentity(ip: "", countryCode: store.networkCountryCode, countryName: "").flagEmoji)
                Text(store.networkEgressKind.title(language: store.language))
                    .lineLimit(1)
                Spacer(minLength: 3)
                Text(store.externalIP)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .help(store.networkCountryName)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: MenuBarQuickAccessPolicy.mainControlHeight)
        .background(palette.cardFill, in: .rect(cornerRadius: 14))
    }

    private var filteredNodes: [ProxyNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.menuBarProxyNodes.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }

    private func nodeSection(palette: GlassPalette) -> some View {
        VStack(spacing: MenuBarQuickAccessPolicy.nodeHeaderSpacing) {
            HStack(spacing: 8) {
                Text(store.text(.menuNodes))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if let selector = store.menuBarSelector {
                    Menu {
                        ForEach(MenuBarProxyResolver.selectors(in: store.proxyGroups)) { group in
                            Button {
                                store.menuBarPreferredGroupName = group.name
                                searchText = ""
                            } label: {
                                if group.name == selector.name {
                                    Label(group.name, systemImage: "checkmark")
                                } else {
                                    Text(group.name)
                                }
                            }
                        }
                    } label: {
                        Text(selector.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 150, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(selector.name)
                }
                Button {
                    isRefreshingNodes = true
                    Task {
                        defer { isRefreshingNodes = false }
                        await store.refreshProxiesAndLatency()
                    }
                } label: {
                    if isRefreshingNodes || store.isLatencyTesting {
                        ProgressView().controlSize(.mini).frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.isRuntimeTransitioning || isRefreshingNodes || store.isLatencyTesting)
                .help(store.text(.delayTest))
                .accessibilityLabel(store.text(.delayTest))
            }
            .frame(height: MenuBarQuickAccessPolicy.nodeHeaderHeight)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(store.text(.search), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.text(.cancel))
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .frame(height: MenuBarQuickAccessPolicy.searchHeight)
            .background(palette.cardFill, in: .rect(cornerRadius: 8))

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        if filteredNodes.isEmpty {
                            Text(store.text(searchText.isEmpty ? .noProxyNodes : .noMatchingNodes))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            ForEach(filteredNodes) { node in
                                MenuBarProxyRow(node: node) {
                                    guard let group = store.menuBarSelector else { return }
                                    Task { await store.selectProxyRemote(groupName: group.name, nodeName: node.name) }
                                }
                                .disabled(store.isRuntimeTransitioning)
                                .id(node.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .onAppear {
                    if let selected = store.menuBarProxyNodes.first(where: \.isSelected) {
                        scrollProxy.scrollTo(selected.id, anchor: .center)
                    }
                }
                .onChange(of: store.menuBarSelector?.name) {
                    if let selected = store.menuBarProxyNodes.first(where: \.isSelected) {
                        scrollProxy.scrollTo(selected.id, anchor: .center)
                    }
                }
            }
            .frame(height: MenuBarQuickAccessPolicy.nodeViewportHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func footer(palette: GlassPalette) -> some View {
        HStack(spacing: 6) {
            if let error = store.lastErrorMessage {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(error)
                    .lineLimit(2)
                    .help(error)
            } else {
                Circle()
                    .fill(store.isStarted ? palette.rose : palette.tertiaryText)
                    .frame(width: 5, height: 5)
                Text(store.isLatencyTesting ? "\(store.text(.checking)) \(store.latencyTestProgress.completed)/\(store.latencyTestProgress.total)" : connectionTitle)
                    .lineLimit(1)
                Spacer()
                Text("\(filteredNodes.count) / \(store.menuBarProxyNodes.count)")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: MenuBarQuickAccessPolicy.footerHeight)
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
            HStack(spacing: 9) {
                Image(systemName: node.isSelected ? "checkmark.circle.fill" : node.isGroup ? "arrow.triangle.branch" : "circle")
                    .font(.system(size: node.isSelected || node.isGroup ? 13 : 7, weight: .medium))
                    .foregroundStyle(node.isSelected ? palette.rose : palette.tertiaryText)
                    .frame(width: 15)
                Text(node.name)
                    .font(.system(size: 12, weight: node.isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if !node.isGroup {
                    Text(node.latency.map { "\($0) ms" } ?? "—")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(latencyColor(palette: palette))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(node.isSelected ? palette.selectionFill : isHovering ? palette.cardFill : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(node.name)
        .accessibilityAddTraits(node.isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovering)
    }

    private func latencyColor(palette: GlassPalette) -> Color {
        guard let latency = node.latency else { return palette.tertiaryText }
        if latency >= ProxyNodeFilter.slowLatencyThreshold { return .orange }
        return colorScheme == .dark ? palette.green : Color(red: 0.14, green: 0.47, blue: 0.34)
    }
}
