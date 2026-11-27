import SwiftUI

struct RoutingView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var input = ""
    @State private var policy: RoutingPolicy = .vpn
    @State private var selectedProxyName: String?
    @State private var isSaving = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    var body: some View {
        let targets = store.availableRoutingProxyTargets
        FeaturePage(
            searchText: $query,
            placeholder: "\(store.text(.search)) \(store.text(.routing))",
            actions: []
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if store.selectedMode != .rule {
                    ruleModeNoticeCard
                }

                editorCard(targets: targets)

                if filteredOverrides.isEmpty {
                    EmptyGlassState(
                        title: store.routingOverrides.isEmpty
                            ? store.text(.addDomainHint)
                            : store.text(.noMatchingRoutingRules),
                        symbol: "arrow.triangle.branch"
                    )
                } else {
                    rulesCard(targets: targets)
                }
            }
        }
        .onChange(of: targets.map(\.name)) { _, names in
            if let selectedProxyName, !names.contains(selectedProxyName) {
                self.selectedProxyName = nil
            }
        }
    }

    private var ruleModeNoticeCard: some View {
        let accent = store.accent.color(for: colorScheme)
        return GlassCard(radius: 14, padding: 12, selectionTint: accent.opacity(0.65)) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(store.text(.routingRuleModeNotice))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                LiquidActionButton(
                    title: store.text(.switchToRuleMode),
                    symbol: "arrow.triangle.branch",
                    tint: accent.opacity(0.28),
                    compact: true
                ) {
                    Task {
                        await store.setOutboundMode(.rule)
                    }
                }
                .disabled(store.isRuntimeTransitioning)
            }
        }
    }

    private func editorCard(targets: [RoutingProxyTarget]) -> some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        return GlassCard(radius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.text(.domainRouting))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(
                            store.selectedManagedProfile.map {
                                store.language.profileStorageDetail(name: $0.name)
                            } ?? store.text(.selectProfileBeforeRules)
                        )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    StatusChip(
                        text: store.language.ruleCount(store.routingOverrides.count),
                        symbol: "list.bullet"
                    )
                }

                routingEditorControls(palette: palette)

                if policy == .customNode {
                    HStack {
                        Text(store.text(.specificNode))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Spacer()
                        RoutingGlassSelector(
                            title: store.text(.selectProxyNode),
                            displayText: selectedProxyName ?? store.text(.selectProxyNode),
                            isPlaceholder: selectedProxyName == nil,
                            targets: targets,
                            language: store.language,
                            accent: store.accent.color(for: colorScheme),
                            showsBuiltInPolicies: false,
                            selectedPolicy: .customNode,
                            selectedProxyName: selectedProxyName,
                            width: 190,
                            height: 36
                        ) { _, chosenName in
                            selectedProxyName = chosenName
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                Text(store.text(.routingExplanation))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                value: policy
            )
        }
    }

    private func routingEditorControls(palette: GlassPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                routingInput(palette: palette)
                    .frame(minWidth: 220)
                routingPolicyPicker
                addRuleButton
            }

            VStack(alignment: .leading, spacing: 10) {
                routingInput(palette: palette)
                HStack(spacing: 10) {
                    routingPolicyPicker
                    Spacer(minLength: 0)
                    addRuleButton
                }
            }
        }
    }

    private func routingInput(palette: GlassPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(palette.tertiaryText)
            TextField("https://example.com/path or example.com", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .onSubmit(addRule)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            palette.selectionTrack,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(palette.selectionStroke.opacity(0.48), lineWidth: 0.8)
        }
    }

    private var routingPolicyPicker: some View {
        PillSegment(
            values: RoutingPolicy.allCases,
            selection: $policy
        ) { policyLabel($0) }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func policyLabel(_ policy: RoutingPolicy) -> String {
        switch policy {
        case .vpn: "VPN"
        case .customNode: store.text(.specificNode)
        case .direct: store.text(.direct)
        }
    }

    private var canAddRule: Bool {
        guard !isSaving,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              store.selectedManagedProfileID != nil else {
            return false
        }
        if policy == .customNode {
            return !(selectedProxyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        return true
    }

    private var addRuleButton: some View {
        LiquidActionButton(
            title: isSaving ? store.text(.saving) : store.text(.addRule),
            symbol: isSaving ? "hourglass" : "plus"
        ) {
            addRule()
        }
        .disabled(!canAddRule)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func rulesCard(targets: [RoutingProxyTarget]) -> some View {
        let availableNames = Set(targets.map(\.name))
        let accent = store.accent.color(for: colorScheme)
        return GlassCard(radius: 16, padding: 0) {
            VStack(spacing: 0) {
                ForEach(filteredOverrides) { routingOverride in
                    let isMissingNode = routingOverride.policy == .customNode
                        && !availableNames.isEmpty
                        && !(routingOverride.proxyName.map(availableNames.contains) ?? false)
                    RoutingOverrideRow(
                        routingOverride: routingOverride,
                        targets: targets,
                        isMissingNode: isMissingNode,
                        language: store.language,
                        accent: accent,
                        isUpdating: isSaving || store.isRuntimeTransitioning,
                        updateTarget: { newPolicy, newProxyName in
                            guard !isSaving else { return }
                            isSaving = true
                            Task {
                                await store.addRoutingOverride(
                                    input: routingOverride.domain,
                                    policy: newPolicy,
                                    proxyName: newProxyName
                                )
                                isSaving = false
                            }
                        },
                        delete: {
                            Task {
                                await store.removeRoutingOverride(domain: routingOverride.domain)
                            }
                        }
                    )
                    if routingOverride.id != filteredOverrides.last?.id {
                        Divider().padding(.leading, 48).opacity(0.12)
                    }
                }
            }
        }
    }

    private var filteredOverrides: [RoutingOverride] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return store.routingOverrides
        }
        return store.routingOverrides.filter {
            $0.domain.localizedCaseInsensitiveContains(trimmed)
                || policyLabel($0.policy).localizedCaseInsensitiveContains(trimmed)
                || ($0.proxyName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func addRule() {
        guard canAddRule else {
            return
        }
        isSaving = true
        Task {
            await store.addRoutingOverride(
                input: input,
                policy: policy,
                proxyName: policy == .customNode ? selectedProxyName : nil
            )
            if store.lastErrorMessage == nil {
                input = ""
            }
            isSaving = false
        }
    }
}

/// Matches LanguageGlassSelector's exact Liquid Glass dropdown button and popover list.
private struct RoutingGlassSelector: View {
    let title: String
    let displayText: String
    var isPlaceholder = false
    let targets: [RoutingProxyTarget]
    let language: AppLanguage
    let accent: Color
    let showsBuiltInPolicies: Bool
    let selectedPolicy: RoutingPolicy
    let selectedProxyName: String?
    var width: CGFloat = 190
    var height: CGFloat = 36
    let onSelect: (RoutingPolicy, String?) -> Void

    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 10) {
                Text(displayText)
                    .foregroundStyle(isPlaceholder ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(LiquidGlassButtonStyle(radius: 12))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
        .accessibilityLabel(title)
        .accessibilityValue(isPlaceholder ? "" : displayText)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            RoutingGlassList(
                title: title,
                targets: targets,
                language: language,
                showsBuiltInPolicies: showsBuiltInPolicies,
                selectedPolicy: selectedPolicy,
                selectedProxyName: selectedProxyName
            ) { newPolicy, newProxyName in
                onSelect(newPolicy, newProxyName)
                isPresented = false
            } dismiss: {
                isPresented = false
            }
            .environment(\.clashGlassReduceMotion, reduceMotion)
            .tint(accent)
            .accentColor(accent)
        }
    }
}

private struct RoutingGlassList: View {
    let title: String
    let targets: [RoutingProxyTarget]
    let language: AppLanguage
    let showsBuiltInPolicies: Bool
    let selectedPolicy: RoutingPolicy
    let selectedProxyName: String?
    let onSelect: (RoutingPolicy, String?) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if showsBuiltInPolicies {
                RoutingGlassRow(
                    title: "VPN",
                    selected: selectedPolicy == .vpn
                ) {
                    onSelect(.vpn, nil)
                }
                RoutingGlassRow(
                    title: language.text(.direct),
                    selected: selectedPolicy == .direct
                ) {
                    onSelect(.direct, nil)
                }
                if !targets.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            }

            if targets.isEmpty && !showsBuiltInPolicies {
                Text(language.text(.noAvailableRoutingNodes))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            } else if !targets.isEmpty {
                ViewThatFits(in: .vertical) {
                    targetRows
                    ScrollView(.vertical) {
                        targetRows
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: 280)
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(8)
        .frame(width: 248)
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private var targetRows: some View {
        let nodes = targets.filter { !$0.isGroup }
        let groups = targets.filter(\.isGroup)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(nodes) { target in
                RoutingGlassRow(
                    title: target.name,
                    selected: selectedPolicy == .customNode && selectedProxyName == target.name
                ) {
                    onSelect(.customNode, target.name)
                }
            }
            if !nodes.isEmpty && !groups.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            ForEach(groups) { target in
                RoutingGlassRow(
                    title: target.name,
                    selected: selectedPolicy == .customNode && selectedProxyName == target.name
                ) {
                    onSelect(.customNode, target.name)
                }
            }
        }
    }
}

private struct RoutingGlassRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(selected ? 1 : 0)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.07 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering && !reduceMotion ? 1.015 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: isHovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RoutingOverrideRow: View {
    let routingOverride: RoutingOverride
    let targets: [RoutingProxyTarget]
    let isMissingNode: Bool
    let language: AppLanguage
    let accent: Color
    let isUpdating: Bool
    let updateTarget: (RoutingPolicy, String?) -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme, accent: accent)
        HStack(spacing: 12) {
            Image(systemName: rowSymbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(rowIconColor(palette: palette))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(routingOverride.domain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Text("DOMAIN-SUFFIX → \(targetLabel)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isMissingNode {
                        Label(language.text(.routingMissingNodeWarning), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            RoutingGlassSelector(
                title: language.text(.changeTarget),
                displayText: targetLabel,
                targets: targets,
                language: language,
                accent: accent,
                showsBuiltInPolicies: true,
                selectedPolicy: routingOverride.policy,
                selectedProxyName: routingOverride.proxyName,
                width: 190,
                height: 32
            ) { newPolicy, newProxyName in
                if newPolicy != routingOverride.policy || newProxyName != routingOverride.proxyName {
                    updateTarget(newPolicy, newProxyName)
                }
            }
            .disabled(isUpdating)

            LiquidIconButton(
                title: language.text(.deleteRule),
                symbol: "trash",
                tint: palette.secondaryText.opacity(0.14),
                size: 28,
                action: delete
            )
            .disabled(isUpdating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var rowSymbol: String {
        switch routingOverride.policy {
        case .vpn: "lock.shield.fill"
        case .customNode: isMissingNode ? "exclamationmark.triangle.fill" : "pin.fill"
        case .direct: "arrow.right"
        }
    }

    private var targetLabel: String {
        switch routingOverride.policy {
        case .vpn: "VPN"
        case .customNode: routingOverride.proxyName ?? language.text(.specificNode)
        case .direct: language.text(.direct)
        }
    }

    private func rowIconColor(palette: GlassPalette) -> Color {
        switch routingOverride.policy {
        case .vpn: palette.rose
        case .customNode: isMissingNode ? .orange : palette.rose
        case .direct: palette.secondaryText
        }
    }
}
