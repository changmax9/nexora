import SwiftUI

struct ConnectionsView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FeaturePage(
            searchText: $query,
            placeholder: "\(store.text(.search)) \(store.text(.connections))",
            actions: [
                .init(title: store.text(.closeAll), symbol: "trash") {
                    Task {
                        await store.closeAllConnections()
                    }
                },
                .init(title: store.text(.refresh), symbol: "arrow.clockwise") {
                    Task {
                        await store.refreshConnections()
                    }
                },
            ]
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusChip(
                        text: "\(store.connections.count) \(store.text(.connections))",
                        symbol: "network"
                    )
                    if filteredConnections.count != store.connections.count {
                        StatusChip(
                            text: "\(filteredConnections.count) \(store.text(.search))",
                            symbol: "line.3.horizontal.decrease.circle"
                        )
                    }
                    Spacer()
                }

                if filteredConnections.isEmpty {
                    EmptyGlassState(title: store.text(.noConnections), symbol: "network.slash")
                } else {
                    GlassCard(radius: 16, padding: 0) {
                        VStack(spacing: 0) {
                            ConnectionHeader(language: store.language)
                            Divider().opacity(0.16)
                            ForEach(filteredConnections) { connection in
                                ConnectionRow(
                                    connection: connection,
                                    showsBlock: true,
                                    closeTitle: store.text(.closeConnection)
                                ) {
                                    Task {
                                        await store.closeConnection(connection)
                                    }
                                }
                                if connection.id != filteredConnections.last?.id {
                                    Divider().padding(.leading, 16).opacity(0.12)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredConnections: [ConnectionEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return store.connections
        }
        return store.connections.filter {
            $0.host.localizedCaseInsensitiveContains(trimmed)
            || $0.rule.localizedCaseInsensitiveContains(trimmed)
            || $0.chain.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

private struct ConnectionHeader: View {
    let language: AppLanguage

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                HeaderText(language.text(.host))
                HeaderText(language.text(.rule))
                HeaderText(language.text(.chain))
                HeaderText(language.text(.upload))
                HeaderText(language.text(.download))
                HeaderText("")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

struct ConnectionRow: View {
    let connection: ConnectionEntry
    let showsBlock: Bool
    var closeTitle = "Close Connection"
    var closeAction: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text(connection.host)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(connection.rule)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Text(connection.chain)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Text(connection.upload)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(connection.download)
                    .monospacedDigit()
                    .lineLimit(1)
                if showsBlock {
                    LiquidIconButton(
                        title: closeTitle,
                        symbol: "xmark",
                        tint: palette.secondaryText.opacity(0.14),
                        size: 24
                    ) {
                        closeAction?()
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct HeaderText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
