import SwiftUI

enum ActiveGlassModal: Identifiable, Equatable {
    case updateCheck(ManualUpdateCheckResult)
    case announcement(Announcement)

    var id: String {
        switch self {
        case let .updateCheck(result):
            switch result {
            case let .updateAvailable(current, latest):
                "update-available-\(current)-\(latest)"
            case let .upToDate(current):
                "update-uptodate-\(current)"
            case let .failed(message):
                "update-failed-\(message)"
            }
        case let .announcement(announcement):
            "announcement-\(announcement.id)"
        }
    }
}

struct AnnouncementModalSheet: View {
    let announcement: Announcement
    @Bindable var store: AppStore
    let onOpenURL: (URL) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = store.accent.color(for: colorScheme)
        let content = announcement.resolvedContent(for: store.language)
        let tintColor = tintColor(accent: accent)
        let badgeTitle = content.badge ?? defaultBadgeTitle
        let actionURL = announcement.validatedActionURL
        let actionLabel = content.actionTitle ?? store.text(.announcementLearnMore)

        GlassModalSheet(
            width: 520,
            symbol: announcement.kind.symbol,
            tintColor: tintColor,
            badgeTitle: badgeTitle,
            metadata: announcement.publishedAt.map(formattedDate),
            title: content.title,
            message: content.body,
            closeTitle: store.text(.close),
            onDismiss: onDismiss
        ) {
            if let actionURL {
                LiquidActionButton(
                    title: actionLabel,
                    symbol: "arrow.up.right.square",
                    wrapsTitle: true
                ) {
                    onOpenURL(actionURL)
                }
                .help(actionLabel)
            }

            LiquidActionButton(
                title: store.text(.announcementAcknowledge),
                symbol: "checkmark",
                tint: tintColor.opacity(0.32),
                action: onDismiss
            )
            .keyboardShortcut(.defaultAction)
        }
    }

    private func tintColor(accent: Color) -> Color {
        switch announcement.kind {
        case .notice, .update: accent
        case .warning: .orange
        case .maintenance: .blue
        }
    }

    private var defaultBadgeTitle: String {
        switch announcement.kind {
        case .notice: store.text(.announcementNoticeBadge)
        case .update: store.text(.announcementUpdateBadge)
        case .warning: store.text(.announcementWarningBadge)
        case .maintenance: store.text(.announcementMaintenanceBadge)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(store.language.locale)
        )
    }
}

struct UpdateCheckModalSheet: View {
    let result: ManualUpdateCheckResult
    @Bindable var store: AppStore
    let onInstallUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = store.accent.color(for: colorScheme)
        let palette = GlassPalette(colorScheme: colorScheme, accent: accent)
        let tintColor = semanticTint(accent: accent, palette: palette)

        GlassModalSheet(
            width: 470,
            symbol: symbolName,
            tintColor: tintColor,
            badgeTitle: store.text(.softwareUpdateBadge),
            metadata: versionMetadata,
            title: titleText,
            message: messageText,
            closeTitle: store.text(.close),
            onDismiss: onDismiss
        ) {
            switch result {
            case .updateAvailable:
                LiquidActionButton(
                    title: store.text(.updateLater),
                    symbol: "clock",
                    tint: nil,
                    action: onDismiss
                )

                LiquidActionButton(
                    title: store.text(.updateWithSparkle),
                    symbol: "arrow.down.circle",
                    tint: tintColor.opacity(0.34),
                    action: onInstallUpdate
                )
                .keyboardShortcut(.defaultAction)

            case .upToDate, .failed:
                LiquidActionButton(
                    title: store.text(.ok),
                    symbol: "checkmark",
                    tint: tintColor.opacity(0.30),
                    action: onDismiss
                )
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var symbolName: String {
        switch result {
        case .updateAvailable: "arrow.down.circle.fill"
        case .upToDate: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func semanticTint(accent: Color, palette: GlassPalette) -> Color {
        switch result {
        case .updateAvailable: accent
        case .upToDate: palette.green
        case .failed: .orange
        }
    }

    private var versionMetadata: String? {
        switch result {
        case let .updateAvailable(current, latest):
            "v\(current) → v\(latest)"
        case let .upToDate(current):
            "v\(current)"
        case .failed:
            nil
        }
    }

    private var titleText: String {
        switch result {
        case .updateAvailable: store.text(.updateAvailableTitle)
        case .upToDate: store.text(.upToDateTitle)
        case .failed: store.text(.updateCheckFailedTitle)
        }
    }

    private var messageText: String {
        switch result {
        case let .updateAvailable(current, latest):
            store.language.updateAvailableMessage(currentVersion: current, latestVersion: latest)
        case let .upToDate(current):
            store.language.upToDateMessage(currentVersion: current)
        case let .failed(detail):
            store.language.updateCheckFailedMessage(detail: detail)
        }
    }
}

/// Draw inside the parent window so the glass can sample the page behind the dialog.
private struct GlassModalSheet<Actions: View>: View {
    let width: CGFloat
    let symbol: String
    let tintColor: Color
    let badgeTitle: String
    let metadata: String?
    let title: String
    let message: String
    let closeTitle: String
    let onDismiss: () -> Void
    @ViewBuilder let actions: () -> Actions

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme, accent: tintColor)

        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        sheetBody(palette: palette)
            .padding(24)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                if reduceTransparency {
                    shape.fill(palette.background)
                } else if #available(macOS 26, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.thinMaterial)
                }
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }

    private func sheetBody(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .vertical) {
                readingContent(palette: palette)
                ScrollView(.vertical) { readingContent(palette: palette) }
                    .frame(height: 352)
            }
            .frame(maxHeight: 352)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                actions()
            }
            .foregroundStyle(palette.primaryText)
        }
    }

    private func readingContent(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tintColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(tintColor.opacity(0.36), lineWidth: 1)
                        }
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(tintColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(badgeTitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(tintColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tintColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(tintColor.opacity(0.30), lineWidth: 0.8)
                            }

                        if let metadata {
                            Text(metadata)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(palette.tertiaryText)
                        }
                    }

                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                LiquidIconButton(
                    title: closeTitle,
                    symbol: "xmark",
                    size: 28,
                    action: onDismiss
                )
                .keyboardShortcut(.cancelAction)
            }

            Divider().opacity(0.14)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
