import SwiftUI

struct RoutingView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var input = ""
    @State private var policy: RoutingPolicy = .vpn
    @State private var isSaving = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FeaturePage(
            searchText: $query,
            placeholder: "\(store.text(.search)) \(store.text(.routing))",
            actions: []
        ) {
            VStack(alignment: .leading, spacing: 14) {
                editorCard

                if filteredOverrides.isEmpty {
                    EmptyGlassState(
                        title: store.routingOverrides.isEmpty
                            ? store.text(.addDomainHint)
                            : store.text(.noMatchingRoutingRules),
                        symbol: "arrow.triangle.branch"
                    )
                } else {
                    rulesCard
                }
            }
        }
    }

    private var editorCard: some View {
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

                Text(store.text(.routingExplanation))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }
        }
    }

    private func routingEditorControls(palette: GlassPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                routingInput(palette: palette)
                    .frame(minWidth: 240)
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
        ) { $0 == .vpn ? "VPN" : store.text(.direct) }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var addRuleButton: some View {
        LiquidActionButton(
            title: isSaving ? store.text(.saving) : store.text(.addRule),
            symbol: isSaving ? "hourglass" : "plus"
        ) {
            addRule()
        }
        .disabled(
            isSaving
                || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || store.selectedManagedProfileID == nil
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var rulesCard: some View {
        GlassCard(radius: 16, padding: 0) {
            VStack(spacing: 0) {
                ForEach(filteredOverrides) { routingOverride in
                    RoutingOverrideRow(
                        routingOverride: routingOverride,
                        language: store.language
                    ) {
                        Task {
                            await store.removeRoutingOverride(domain: routingOverride.domain)
                        }
                    }
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
                || $0.policy.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func addRule() {
        guard !isSaving else {
            return
        }
        isSaving = true
        Task {
            await store.addRoutingOverride(input: input, policy: policy)
            if store.lastErrorMessage == nil {
                input = ""
            }
            isSaving = false
        }
    }
}

private struct RoutingOverrideRow: View {
    let routingOverride: RoutingOverride
    let language: AppLanguage
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 12) {
            Image(systemName: routingOverride.policy == .vpn ? "lock.shield.fill" : "arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(routingOverride.policy == .vpn ? palette.rose : palette.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(routingOverride.domain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(
                    "DOMAIN-SUFFIX → \(routingOverride.policy == .vpn ? "VPN" : language.text(.direct))"
                )
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }
            Spacer()
            StatusChip(
                text: routingOverride.policy == .vpn ? "VPN" : language.text(.direct),
                symbol: routingOverride.policy == .vpn ? "network.badge.shield.half.filled" : nil,
                tint: routingOverride.policy == .vpn ? palette.rose : palette.secondaryText
            )
            LiquidIconButton(
                title: language.text(.deleteRule),
                symbol: "trash",
                tint: palette.secondaryText.opacity(0.14),
                size: 28,
                action: delete
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
