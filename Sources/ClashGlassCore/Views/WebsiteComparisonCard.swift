import AppKit
import SwiftUI

struct WebsiteComparisonCard: View {
    @Bindable var store: AppStore
    @Bindable private var comparison: WebsiteComparisonStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isURLFocused: Bool

    init(store: AppStore) {
        self.store = store
        comparison = store.websiteComparison
    }

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        GlassCard(radius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                heading(palette: palette)
                input(palette: palette)
                if comparison.isInputInvalid {
                    Label(store.text(.websiteInvalidURL), systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.isTunEnabled || (comparison.result?.context.hasSystemTunnel == true && !comparison.isStale) {
                    Label(store.text(.websiteTunnelWarning), systemImage: "network.badge.shield.half.filled")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().opacity(0.15)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], alignment: .leading, spacing: 14) {
                    ForEach(WebsiteProbeRoute.allCases) { route in
                        resultColumn(route: route, palette: palette)
                    }
                }
                if comparison.isStale {
                    Label(store.text(.websiteStaleHint), systemImage: "arrow.clockwise.circle")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if comparison.wasCancelled {
                    Text(store.text(.websiteCancelled))
                        .font(.system(size: 11)).foregroundStyle(palette.secondaryText)
                }
                if let result = comparison.result {
                    HStack {
                        Text(result.url.host ?? "")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(result.date, style: .time)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.tertiaryText)
                }
            }
        }
        .environment(\.locale, store.language.locale)
    }

    private func heading(palette: GlassPalette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Label(store.text(.websiteComparisonTitle), systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(store.text(.websiteComparisonHint))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                guard let result = comparison.result else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.copyText(language: store.language), forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.text(.websiteCopyResults))
            .help(store.text(.websiteCopyResults))
            .disabled(comparison.result == nil || comparison.isRunning || comparison.isStale)
        }
    }

    private func input(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.text(.websiteURL))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 10) {
                TextField(store.text(.websiteURLPlaceholder), text: $comparison.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(palette.selectionTrack, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isURLFocused ? Color.accentColor : palette.selectionStroke, lineWidth: isURLFocused ? 2 : 0.8)
                    }
                    .focused($isURLFocused)
                    .accessibilityLabel(store.text(.websiteURL))
                    .accessibilityIdentifier("website.url")
                    .autocorrectionDisabled()
                    .onSubmit(compare)
                    .disabled(comparison.isRunning)
                    .frame(minWidth: 0)
                LiquidActionButton(
                    title: comparison.isRunning ? store.text(.cancel) : store.text(.websiteCompare),
                    symbol: comparison.isRunning ? "xmark" : "arrow.left.arrow.right"
                ) {
                    if comparison.isRunning { comparison.cancel() } else { compare() }
                }
                .disabled(!comparison.isRunning && comparison.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func resultColumn(route: WebsiteProbeRoute, palette: GlassPalette) -> some View {
        let result = comparison.result?.results.first { $0.route == route }
        let mode = comparison.result?.context.mode ?? store.selectedMode
        let title = route == .direct ? store.text(.websiteDirectRoute)
            : "\(store.text(.websiteNexoraRoute)) · \(store.text(mode.titleKey))"
        let restricted = result.map { $0.receivedResponse && !$0.isSuccessfulHTTP } ?? false
        return VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded))
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if comparison.isRunning {
                    ProgressView().controlSize(.mini)
                    Text(store.text(.checking))
                } else if let result {
                    Image(systemName: result.isSuccessfulHTTP ? "checkmark.circle.fill"
                          : result.receivedResponse ? "exclamationmark.circle" : "xmark.circle")
                        .foregroundStyle(result.isSuccessfulHTTP ? Color.green : result.receivedResponse ? .orange : .secondary)
                    Text(result.statusText(language: store.language))
                } else {
                    Image(systemName: "minus.circle").foregroundStyle(palette.tertiaryText)
                    Text(store.text(.websiteWaiting)).foregroundStyle(palette.tertiaryText)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)

            Text(restricted
                 ? store.text(.websiteHTTPRestricted)
                 : store.text(route == .direct ? .websiteDirectHint : .websiteNexoraHint))
                .font(.system(size: 11)).foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let result, let total = result.latencyMilliseconds {
                HStack(spacing: 14) {
                    Text("\(store.text(.websiteTotalTime)) \(total) ms")
                    if let dns = result.dnsMilliseconds {
                        Text("\(store.text(.websiteDNSTime)) \(dns) ms")
                    }
                }
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func compare() {
        guard !comparison.isRunning else { return }
        Task { await store.compareWebsite() }
    }
}
