import SwiftUI

private enum ProxiesDisplayMode: String, CaseIterable, Identifiable {
    case tab
    case list

    var id: Self { self }
}

struct ProxiesView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var displayMode: ProxiesDisplayMode = .tab
    @State private var nodeFilter: ProxyNodeFilter = .all
    @State private var expansionState = ProxyGroupExpansionState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    var body: some View {
        FeaturePage(
            searchText: $query,
            placeholder: "\(store.text(.search)) \(store.text(.proxies))",
            actions: toolbarActions
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        PillSegment(
                            values: ProxiesDisplayMode.allCases,
                            selection: $displayMode
                        ) { displayModeTitle($0) }
                        Spacer()
                        if store.isLatencyTesting {
                            ProgressView(value: store.latencyTestProgress.fraction)
                                .progressViewStyle(.linear)
                                .frame(width: 72)
                            StatusChip(
                                text: store.latencyTestProgress.text,
                                symbol: "waveform.path.ecg"
                            )
                        } else {
                            StatusChip(
                                text: "\(filteredGroups.reduce(0) { $0 + $1.nodes.count }) \(store.text(.nodes))",
                                symbol: "point.3.connected.trianglepath.dotted"
                            )
                        }
                    }

                    PillSegment(
                        values: ProxyNodeFilter.allCases,
                        selection: $nodeFilter
                    ) { $0.title(language: store.language) }
                }

                if filteredGroups.isEmpty {
                    EmptyGlassState(title: store.text(.noProxyNodes), symbol: "point.3.connected.trianglepath.dotted")
                } else if displayMode == .tab {
                    tabContent
                } else {
                    listContent
                }
            }
        }
    }

    private var toolbarActions: [FeatureAction] {
        [
            FeatureAction(
                title: store.isLatencyTesting ? store.latencyTestProgress.text : store.text(.refresh),
                symbol: store.isLatencyTesting ? "hourglass" : "arrow.clockwise",
                isDisabled: store.isLatencyTesting
            ) {
                Task { await store.refreshProxiesAndLatency() }
            },
            FeatureAction(title: store.text(.settings), symbol: "slider.horizontal.3") {
                store.selectedSection = .settings
            },
        ]
    }

    private var filteredGroups: [ProxyGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.proxyGroups.compactMap { group in
            let groupMatchesQuery = trimmed.isEmpty
                || group.name.localizedCaseInsensitiveContains(trimmed)
            let nodes = group.nodes.filter {
                let matchesNodeFilter = nodeFilter.matches($0)
                let matchesQuery = groupMatchesQuery
                    || $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.region.localizedCaseInsensitiveContains(trimmed)
                return matchesNodeFilter && matchesQuery
            }
            guard !nodes.isEmpty else { return nil }
            return ProxyGroup(
                name: group.name,
                policy: group.policy,
                kind: group.kind,
                testURL: group.testURL,
                nodes: nodes
            )
        }
    }

    private var tabContent: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(filteredGroups) { group in
                let isExpanded = expansionState.isExpanded(group.name)
                GlassCard(radius: 16, padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.down.right.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text(group.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            StatusChip(
                                text: group.kind.isAutomatic
                                    ? "\(store.text(.automatic)) · \(store.language.localizedProxyType(group.policy))"
                                    : store.language.localizedProxyType(group.policy),
                                symbol: group.kind.isAutomatic ? "bolt.horizontal.circle" : nil,
                                tint: palette.rose
                            )
                            Spacer()
                            StatusChip(text: "\(group.nodes.count)", symbol: "server.rack")
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78)) {
                                    expansionState.toggle(group.name)
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 24, height: 24)
                                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            }
                            .buttonStyle(.plain)
                            .contentShape(Circle())
                            .help(
                                "\(isExpanded ? store.text(.collapse) : store.text(.expand)) \(group.name)"
                            )
                        }
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if isExpanded {
                            Divider().opacity(0.16)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 10)], spacing: 10) {
                                ForEach(group.nodes) { node in
                                    ProxyNodeCard(
                                        node: node,
                                        displayRegion: store.language.localizedProxyType(node.region),
                                        isTesting: store.isLatencyTesting
                                    ) {
                                        Task {
                                            await store.selectProxyRemote(groupName: group.name, nodeName: node.name)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .transition(
                                .opacity.combined(
                                    with: .move(edge: .top)
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private var listContent: some View {
        GlassCard(radius: 16, padding: 0) {
            VStack(spacing: 0) {
                ForEach(filteredGroups) { group in
                    ForEach(group.nodes) { node in
                        ProxyNodeRow(
                            group: group.name,
                            node: node,
                            displayRegion: store.language.localizedProxyType(node.region),
                            isTesting: store.isLatencyTesting
                        ) {
                            Task {
                                await store.selectProxyRemote(groupName: group.name, nodeName: node.name)
                            }
                        }
                        Divider().padding(.leading, 46).opacity(0.14)
                    }
                }
            }
        }
    }

    private func displayModeTitle(_ mode: ProxiesDisplayMode) -> String {
        switch mode {
        case .tab: store.text(.tab)
        case .list: store.text(.list)
        }
    }
}

private struct ProxyNodeCard: View {
    let node: ProxyNode
    let displayRegion: String
    let isTesting: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: node.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(node.isSelected ? palette.rose : palette.tertiaryText)
                    Spacer()
                    Text(latencyText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(latencyColor(palette: palette))
                }
                Text(node.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(displayRegion)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                node.isSelected ? palette.selectionFill : palette.cardFill,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(node.isSelected ? palette.selectionStroke : palette.cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !reduceMotion ? 1.018 : 1)
        .offset(y: isHovering && !reduceMotion ? -1.5 : 0)
        .brightness(isHovering ? 0.02 : 0)
        .shadow(color: .black.opacity(isHovering && !reduceMotion ? 0.10 : 0), radius: 9, y: 5)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72),
            value: isHovering
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78),
            value: node.isSelected
        )
    }

    private var latencyText: String {
        node.latency.map { "\($0) ms" } ?? (isTesting ? "…" : "—")
    }

    private func latencyColor(palette: GlassPalette) -> Color {
        guard let latency = node.latency else {
            return palette.tertiaryText
        }
        return latency < 180 ? palette.green : .orange
    }
}

private struct ProxyNodeRow: View {
    let group: String
    let node: ProxyNode
    let displayRegion: String
    let isTesting: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: node.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(node.isSelected ? palette.rose : palette.secondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(group)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                }
                Spacer()
                StatusChip(text: displayRegion, symbol: nil)
                Text(latencyText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(latencyColor(palette: palette))
                    .frame(width: 58, alignment: .trailing)
            }
            .foregroundStyle(palette.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                node.isSelected
                    ? palette.selectionFill
                    : isHovering ? palette.selectionHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.76),
            value: isHovering
        )
    }

    private var latencyText: String {
        node.latency.map { "\($0) ms" } ?? (isTesting ? "…" : "—")
    }

    private func latencyColor(palette: GlassPalette) -> Color {
        guard let latency = node.latency else {
            return palette.tertiaryText
        }
        return latency < 180 ? palette.green : .orange
    }
}
