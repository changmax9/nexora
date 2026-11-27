import SwiftUI

struct DiagnosticExplanationCard: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var hasSnapshot: Bool {
        store.networkDiagnosticReportDate != nil && !store.isDiagnosticExplanationStale
    }

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)

        GlassCard(radius: 16, padding: 0) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        heading(palette: palette)
                        Spacer(minLength: 12)
                        explanationAction
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        heading(palette: palette)
                        explanationAction
                    }
                }

                if let explanation = store.diagnosticExplanation {
                    if store.isDiagnosticExplanationStale {
                        Label(store.text(.diagnosticExplanationStaleHint), systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(explanation.summary)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if !explanation.observations.isEmpty {
                        explanationRows(
                            title: store.text(.diagnosticExplanationEvidence),
                            items: explanation.observations,
                            numbered: false,
                            palette: palette
                        )
                    }

                    if !explanation.nextSteps.isEmpty {
                        explanationRows(
                            title: store.text(.diagnosticExplanationNextSteps),
                            items: explanation.nextSteps,
                            numbered: true,
                            palette: palette
                        )
                    }

                    if store.diagnosticExplanationDidFallback {
                        Label(store.text(.diagnosticExplanationFallback), systemImage: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        if let unavailableText {
                            Text(unavailableText)
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(store.text(.diagnosticExplanationSnapshotHint))
                            .foregroundStyle(palette.tertiaryText)
                        Text(store.text(.diagnosticExplanationPrivacyHint))
                            .foregroundStyle(palette.tertiaryText)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.text(.diagnosticExplanationPlaceholder))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { store.refreshDiagnosticModelAvailability() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshDiagnosticModelAvailability() }
        }
    }

    private func heading(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(store.text(.diagnosticExplanationTitle))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = store.diagnosticExplanation {
                    Text(store.text(explanation.source == .onDeviceModel
                        ? .diagnosticExplanationModel : .diagnosticExplanationRules))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.selectionTrack, in: Capsule())
                        .fixedSize()
                }
            }
            if store.diagnosticExplanation != nil {
                HStack(spacing: 8) {
                    if store.isDiagnosticExplanationStale {
                        Label(store.text(.diagnosticExplanationStale), systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                    if let date = store.diagnosticExplanationDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute().locale(store.language.locale))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
            }
        }
        .foregroundStyle(palette.secondaryText)
    }

    @ViewBuilder
    private var explanationAction: some View {
        if store.isExplainingDiagnosis {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                    .accessibilityHidden(true)
                Text(store.text(.diagnosticExplanationGenerating))
                    .font(.system(size: 11, weight: .medium))
                LiquidActionButton(title: store.text(.cancel), symbol: "xmark", compact: true) {
                    store.cancelDiagnosticExplanation()
                }
            }
        } else if hasSnapshot, store.diagnosticModelAvailability == .available {
            LiquidActionButton(
                title: store.text(.diagnosticExplanationAIAction),
                symbol: "sparkles",
                compact: true
            ) {
                Task { await store.explainNetworkDiagnosis() }
            }
            .disabled(store.isRunningNetworkDiagnosis)
        }
    }

    private func explanationRows(
        title: String,
        items: [String],
        numbered: Bool,
        palette: GlassPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(numbered ? "\(index + 1)." : "•")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                        .frame(minWidth: 14, alignment: .leading)
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(numbered ? "\(index + 1). \(item)" : item)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailableText: String? {
        switch store.diagnosticModelAvailability {
        case .available: nil
        case .unsupportedSystem: store.text(.diagnosticExplanationUnsupportedSystem)
        case .intelligenceDisabled: store.text(.diagnosticExplanationIntelligenceDisabled)
        case .modelNotReady: store.text(.diagnosticExplanationModelNotReady)
        case .deviceIneligible: store.text(.diagnosticExplanationDeviceIneligible)
        case .unavailable: store.text(.diagnosticExplanationModelUnavailable)
        }
    }
}
