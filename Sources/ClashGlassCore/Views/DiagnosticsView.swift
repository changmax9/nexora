import AppKit
import SwiftUI

enum DiagnosticsToolbarLayoutMetrics {
    static let checksWidth: CGFloat = 90
    static let exitWidth: CGFloat = 118
    static let profileWidth: CGFloat = 84

    static func width(for symbol: String) -> CGFloat {
        switch symbol {
        case "checklist": checksWidth
        case "globe": exitWidth
        default: profileWidth
        }
    }
}

struct DiagnosticsView: View {
    @Bindable var store: AppStore

    var body: some View {
        FeaturePage(
            toolbarLeading: AnyView(DiagnosticsToolbarBrief(store: store)),
            placeholder: "",
            actions: [
                FeatureAction(title: store.text(.copyReport), symbol: "doc.on.doc", isDisabled: store.networkDiagnosticReport.findings.isEmpty) {
                    copyNetworkDoctorReport(store.networkDiagnosticReport.copyText)
                },
                FeatureAction(title: store.text(.diagnose), symbol: "stethoscope") {
                    Task {
                        await store.runNetworkDiagnosis()
                    }
                },
            ]
        ) {
            VStack(alignment: .leading, spacing: 14) {
                DiagnosticsStatusStrip(store: store)
                NetworkDoctorOverviewCard(store: store)
                DiagnosticsSectionCard(
                    symbol: "list.bullet.rectangle",
                    title: store.text(.findings),
                    count: store.networkDiagnosticReport.findings.count
                ) {
                    NetworkDoctorFindingsList(
                        report: store.networkDiagnosticReport,
                        placeholderText: store.text(.networkDiagnosisHint)
                    )
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
                    DiagnosticsSectionCard(
                        symbol: "dot.radiowaves.left.and.right",
                        title: store.text(.portRadar),
                        count: store.networkPortChecks.count
                    ) {
                        PortRadarList(store: store)
                    }

                    DiagnosticsSectionCard(
                        symbol: "network",
                        title: store.text(.dnsProbe),
                        count: store.networkDNSChecks.count
                    ) {
                        DNSProbeList(store: store)
                    }

                    DiagnosticsSectionCard(
                        symbol: "antenna.radiowaves.left.and.right",
                        title: store.text(.endpointProbe),
                        count: store.networkEndpointChecks.count
                    ) {
                        EndpointProbeList(store: store)
                    }
                }
            }
        }
    }
}

private struct DiagnosticsToolbarBrief: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    private var totalChecks: Int {
        store.networkPortChecks.count
            + store.networkDNSChecks.count
            + store.networkEndpointChecks.count
    }

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let brief = NetworkDiagnosticBrief.make(
            report: store.networkDiagnosticReport,
            totalChecks: totalChecks,
            egressTitle: store.networkEgressKind.title(language: store.language),
            profileTitle: store.menuBarProfileTitle,
            language: store.language
        )
        let tint = diagnosticTint(brief.severity, palette: palette)

        GlassCard(radius: 16, padding: 0) {
            HStack(spacing: 12) {
                Image(systemName: brief.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(brief.headline)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(brief.detail)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(minWidth: 174, maxWidth: 240, alignment: .leading)

                HStack(spacing: 7) {
                    ForEach(brief.metrics, id: \.title) { metric in
                        DiagnosticsToolbarMetric(
                            metric: metric,
                            width: DiagnosticsToolbarLayoutMetrics.width(for: metric.symbol)
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: 560, minHeight: 56, maxHeight: 56, alignment: .leading)
    }
}

private struct DiagnosticsToolbarMetric: View {
    let metric: NetworkDiagnosticBriefMetric
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(metric.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .foregroundStyle(palette.tertiaryText)

            Text(metric.value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 38, alignment: .leading)
        .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DiagnosticsStatusStrip: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let report = store.networkDiagnosticReport
        let tint = diagnosticTint(report.severity, palette: palette)

        HStack(spacing: 8) {
            StatusChip(
                text: severityTitle(report.severity, language: store.language),
                symbol: report.severity.symbol,
                tint: tint
            )
            StatusChip(text: store.networkEgressKind.title(language: store.language), symbol: "globe")
            StatusChip(text: store.text(store.selectedMode.titleKey), symbol: "switch.2")
            StatusChip(text: "\(store.networkPortChecks.count + store.networkDNSChecks.count + store.networkEndpointChecks.count)", symbol: "checklist")
            Spacer(minLength: 0)
        }
    }
}

private struct NetworkDoctorOverviewCard: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let report = store.networkDiagnosticReport
        let tint = diagnosticTint(report.severity, palette: palette)
        let isPlaceholder = report.findings.isEmpty

        GlassCard(radius: 16, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: report.severity.symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.text(.networkDoctor))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.primaryText)
                        Text(isPlaceholder ? store.text(.runNetworkDoctor) : report.summary)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                            Text(isPlaceholder ? store.text(.networkDiagnosisHint) : report.suggestedAction)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.tertiaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 7) {
                        DiagnosticMetricPill(title: store.externalIP, symbol: "number")
                        DiagnosticMetricPill(title: store.intranetIP, symbol: "network")
                        DiagnosticMetricPill(title: store.menuBarProfileTitle, symbol: "doc.text")
                    }
                    .frame(maxWidth: 210, alignment: .trailing)
                }
                .padding(16)
            }
        }
    }
}

private struct DiagnosticsSectionCard<Content: View>: View {
    let symbol: String
    let title: String
    let count: Int
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)

        GlassCard(radius: 16, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 18)
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    StatusChip(text: count == 0 ? "0" : "\(count)", symbol: nil)
                }
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider().opacity(0.14)

                content
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NetworkDoctorFindingsList: View {
    let report: NetworkDiagnosticReport
    let placeholderText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            if report.findings.isEmpty {
                DiagnosticPlaceholderRow(text: placeholderText, symbol: "stethoscope")
            } else {
                ForEach(report.findings) { finding in
                    NetworkDoctorFindingRow(finding: finding)
                }
            }
        }
    }
}

private struct NetworkDoctorFindingRow: View {
    let finding: NetworkDiagnosticFinding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let tint = diagnosticTint(finding.severity, palette: palette)

        HStack(alignment: .top, spacing: 11) {
            Image(systemName: finding.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(finding.detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PortRadarList: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 8) {
            if store.networkPortChecks.isEmpty {
                DiagnosticPlaceholderRow(text: store.text(.networkDiagnosisHint), symbol: "dot.radiowaves.left.and.right")
            } else {
                ForEach(store.networkPortChecks) { check in
                    PortRadarRow(check: check)
                }
            }
        }
    }
}

private struct PortRadarRow: View {
    let check: NetworkPortCheck
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 11) {
            DiagnosticStateDot(color: check.isListening ? palette.green : palette.tertiaryText.opacity(0.65))
            Text(check.label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
            Text(":\(check.port)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
            Spacer(minLength: 8)
            Text(check.ownerDescription)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DNSProbeList: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 8) {
            if store.networkDNSChecks.isEmpty {
                DiagnosticPlaceholderRow(text: store.text(.networkDiagnosisHint), symbol: "network")
            } else {
                ForEach(store.networkDNSChecks) { check in
                    DNSProbeRow(check: check)
                }
            }
        }
    }
}

private struct DNSProbeRow: View {
    let check: NetworkDNSCheck
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 11) {
            DiagnosticStateDot(color: check.isResolved ? palette.green : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.host)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(check.detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct EndpointProbeList: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 8) {
            if store.networkEndpointChecks.isEmpty {
                DiagnosticPlaceholderRow(text: store.text(.networkDiagnosisHint), symbol: "antenna.radiowaves.left.and.right")
            } else {
                ForEach(store.networkEndpointChecks) { check in
                    EndpointProbeRow(check: check)
                }
            }
        }
    }
}

private struct EndpointProbeRow: View {
    let check: NetworkEndpointCheck
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let tint: Color = if !check.isReachable {
            .red
        } else if (check.latencyMilliseconds ?? 0) > 1_500 {
            .orange
        } else {
            palette.green
        }

        HStack(spacing: 11) {
            DiagnosticStateDot(color: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(check.statusDescription)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(check.latencyDescription)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DiagnosticPlaceholderRow: View {
    let text: String
    let symbol: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.tertiaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DiagnosticStateDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }
}

private struct DiagnosticMetricPill: View {
    let title: String
    let symbol: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(palette.selectionTrack, in: Capsule(style: .continuous))
    }
}

private func severityTitle(_ severity: NetworkDiagnosticSeverity, language: AppLanguage) -> String {
    switch severity {
    case .healthy: language.text(.ready)
    case .warning: language.text(.warnings)
    case .critical: language.text(.errors)
    }
}

private func diagnosticTint(_ severity: NetworkDiagnosticSeverity, palette: GlassPalette) -> Color {
    switch severity {
    case .healthy: palette.green
    case .warning: .orange
    case .critical: .red
    }
}

private func copyNetworkDoctorReport(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
