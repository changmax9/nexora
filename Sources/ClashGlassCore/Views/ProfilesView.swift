import SwiftUI

struct ProfilesView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var healthFilter: ProfileHealthFilter = .all
    @State private var renameProfileID: ManagedProfile.ID?
    @State private var renameDraft = ""
    @State private var showsProfileRename = false
    @State private var profilePendingDeletion: ManagedProfile?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FeaturePage(
            searchText: $query,
            placeholder: "\(store.text(.search)) \(store.text(.profiles))",
            actions: [
                .init(
                    title: store.text(.refresh), symbol: "arrow.clockwise",
                    isDisabled: store.isRefreshingProfileTrafficUsage
                        || !store.managedProfiles.contains(where: { $0.subscriptionURL != nil })
                ) {
                    Task { await store.refreshManagedProfileTrafficUsage() }
                },
                .init(title: store.text(.validateAll), symbol: "checkmark.shield") {
                    Task { await store.validateAllManagedProfiles() }
                },
                .init(title: store.text(.openManagedFolder), symbol: "folder") {
                    ConfigurationFilePanel.reveal(store.managedProfilesFolderURL)
                },
            ],
            toolbarTrailing: AnyView(ProfileImportButton(store: store))
        ) {
            if store.managedProfiles.isEmpty {
                GlassCard(radius: 16, padding: 26) {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(store.text(.importConfiguration))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        LiquidActionButton(title: store.text(.importConfiguration), symbol: "square.and.arrow.down") {
                            importYAML()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 210)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    PillSegment(
                        values: ProfileHealthFilter.allCases,
                        selection: $healthFilter
                    ) { filter in
                        filter.title(language: store.language)
                    }

                    if filteredProfiles.isEmpty {
                        EmptyGlassState(
                            title: store.text(.noMatchingProfiles),
                            symbol: "line.3.horizontal.decrease.circle"
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                            ForEach(filteredProfiles) { profile in
                                ManagedProfileCard(
                                    profile: profile,
                                    isSelected: profile.id == store.selectedManagedProfileID,
                                    isRunning: profile.id == store.selectedManagedProfileID && store.isStarted,
                                    validationState: store.validationState(for: profile.id),
                                    language: store.language,
                                    refreshFailed: store.profileTrafficRefreshFailures.contains(profile.id),
                                    select: {
                                        guard profile.id != store.selectedManagedProfileID,
                                              !store.isRuntimeTransitioning else { return }
                                        Task { await store.selectManagedProfile(profile.id) }
                                    },
                                    validate: {
                                        Task { await store.validateManagedProfile(profile.id) }
                                    },
                                    reveal: {
                                        ConfigurationFilePanel.reveal(profile.managedConfigURL)
                                    },
                                    rename: {
                                        renameProfileID = profile.id
                                        renameDraft = profile.name
                                        showsProfileRename = true
                                    },
                                    delete: {
                                        profilePendingDeletion = profile
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .task { await store.refreshManagedProfileTrafficUsage() }
        .dropDestination(for: URL.self) { urls, _ in
            let yamlURLs = urls.filter {
                $0.isFileURL && ["yaml", "yml"].contains($0.pathExtension.lowercased())
            }
            for url in yamlURLs {
                Task { await store.importManagedProfile(from: url) }
            }
            return !yamlURLs.isEmpty
        }
        .alert(store.text(.renameProfile), isPresented: $showsProfileRename) {
            TextField(store.text(.profileName), text: $renameDraft)
            Button(store.text(.cancel), role: .cancel) {
                renameProfileID = nil
            }
            Button(store.text(.rename)) {
                guard let renameProfileID else { return }
                store.renameManagedProfile(renameProfileID, to: renameDraft)
                self.renameProfileID = nil
            }
        } message: {
            Text(store.text(.renameMenuBarNote))
        }
        .confirmationDialog(
            store.language.deleteProfilePrompt(name: profilePendingDeletion?.name),
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { if !$0 { profilePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(store.text(.deleteProfile), role: .destructive) {
                guard let profilePendingDeletion else { return }
                Task { await store.removeManagedProfile(profilePendingDeletion.id) }
                self.profilePendingDeletion = nil
            }
            Button(store.text(.cancel), role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: {
            Text(store.text(.deleteProfileExplanation))
        }
    }

    private var filteredProfiles: [ManagedProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.managedProfiles.filter {
            let validationState = store.validationState(for: $0.id)
            let matchesHealth = healthFilter.matches(validationState)
            let matchesQuery = trimmed.isEmpty
                || $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.managedConfigURL.path.localizedCaseInsensitiveContains(trimmed)
            return matchesHealth && matchesQuery
        }
    }

    private func importYAML() {
        guard let url = ConfigurationFilePanel.chooseYAML() else {
            return
        }
        Task {
            await store.importManagedProfile(from: url)
        }
    }
}

enum ProfileCardActionLayoutMetrics {
    static let spacing: CGFloat = 8
    static let minimumGap: CGFloat = 8
    static let usesStackedFallback = true
    static let secondaryActionsWidth = CGFloat(ToolbarControlMetrics.hitTarget) * 4 + spacing * 3
}

private struct ManagedProfileCard: View {
    let profile: ManagedProfile
    let isSelected: Bool
    let isRunning: Bool
    let validationState: ProfileValidationState
    let language: AppLanguage
    let refreshFailed: Bool
    let select: () -> Void
    let validate: () -> Void
    let reveal: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Button(action: select) {
            GlassCard(radius: 16, padding: 16, selectionTint: isSelected ? palette.rose : nil) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: isRunning ? "bolt.circle.fill" : isSelected ? "checkmark.seal.fill" : "doc.text.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isRunning ? palette.green : isSelected ? palette.rose : palette.secondaryText)
                        Spacer()
                        StatusChip(
                            text: isRunning
                                ? language.text(.running)
                                : isSelected
                                    ? language.text(.current)
                                    : language.text(.managed),
                            symbol: nil,
                            tint: isRunning ? palette.green : isSelected ? palette.rose : nil
                        )
                    }
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Text(language.text(.managedYAML))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.secondaryText)
                        ProfileValidationLine(
                            state: validationState,
                            language: language,
                            palette: palette
                        )
                        Text(profile.importedAt, style: .relative)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.tertiaryText)
                    }
                    .allowsHitTesting(false)

                    trafficFooter(palette: palette)
                }
                .frame(maxWidth: .infinity, minHeight: 198, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("\(language.text(.use)) \(profile.name)")
        .accessibilityValue(selectionAccessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Sibling controls avoid nested buttons and keep their actions independent.
        .overlay(alignment: .bottomTrailing) {
            secondaryActionButtons(palette: palette)
                .padding(16)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isSelected)
    }

    private func trafficFooter(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fraction = profile.trafficUsage?.remainingFraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.selectionTrack)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [palette.rose.opacity(0.65), palette.rose],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * fraction)
                    }
                    .overlay {
                        Capsule().strokeBorder(palette.cardStroke.opacity(0.6), lineWidth: 0.5)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ProfileCardActionLayoutMetrics.spacing) {
                    trafficLabels(palette: palette)
                    Spacer(minLength: ProfileCardActionLayoutMetrics.minimumGap)
                    actionSpace
                }

                VStack(alignment: .leading, spacing: ProfileCardActionLayoutMetrics.spacing) {
                    trafficLabels(palette: palette)
                    actionSpace.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .help(trafficUsageHelp)
    }

    private var actionSpace: some View {
        Color.clear
            .frame(
                width: ProfileCardActionLayoutMetrics.secondaryActionsWidth,
                height: CGFloat(ToolbarControlMetrics.hitTarget)
            )
            .accessibilityHidden(true)
    }

    private func trafficLabels(palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(remainingGBText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primaryText)
            Text(remainingPercentText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText)
        }
        .monospacedDigit()
        .frame(minWidth: 100, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var remainingGBText: String {
        guard let gigabytes = profile.trafficUsage?.remainingGigabytes else {
            return language.text(.profileTrafficUnavailable)
        }
        let value = gigabytes.formatted(.number.precision(.fractionLength(2)).locale(language.locale))
        return String(format: language.text(.profileTrafficLeftGBFormat), value)
    }

    private var remainingPercentText: String {
        if refreshFailed { return language.text(.profileTrafficRefreshFailed) }
        guard let fraction = profile.trafficUsage?.remainingFraction else {
            if profile.trafficUsage?.remainingBytes != nil {
                return language.text(.profileTrafficSnapshot)
            }
            return language.text(profile.subscriptionURL == nil ? .profileTrafficLocal : .profileTrafficNotReported)
        }
        let value = fraction.formatted(.percent.precision(.fractionLength(1)).locale(language.locale))
        return String(format: language.text(.profileTrafficLeftPercentFormat), value)
    }

    private var trafficUsageHelp: String {
        guard let usage = profile.trafficUsage, usage.remainingBytes != nil else {
            return language.text(profile.subscriptionURL == nil ? .profileTrafficLocalHelp : .profileTrafficNotReportedHelp)
        }
        let date = usage.updatedAt.formatted(
            .dateTime.month().day().hour().minute().locale(language.locale)
        )
        let key: AppString = usage.source == .configuration || profile.subscriptionURL == nil
            ? .profileTrafficSnapshotHelpFormat : .profileTrafficUpdatedFormat
        let description = String(format: language.text(key), date)
        return refreshFailed ? description + "\n" + language.text(.profileTrafficRefreshFailed) : description
    }

    private var selectionAccessibilityValue: String {
        [isSelected ? language.text(.selected) : "", remainingGBText, remainingPercentText]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func secondaryActionButtons(palette: GlassPalette) -> some View {
        HStack(spacing: ProfileCardActionLayoutMetrics.spacing) {
            LiquidIconButton(title: language.text(.validate), symbol: "checkmark.shield", size: 28, action: validate)
            LiquidIconButton(title: language.text(.revealInFinder), symbol: "folder", size: 28, action: reveal)
            LiquidIconButton(title: language.text(.rename), symbol: "pencil", size: 28, action: rename)
            LiquidIconButton(
                title: language.text(.delete),
                symbol: "trash",
                tint: palette.secondaryText.opacity(0.14),
                size: 28,
                action: delete
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ProfileValidationLine: View {
    let state: ProfileValidationState
    let language: AppLanguage
    let palette: GlassPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: state.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(state.title(language: language))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if let checkedAt = state.checkedAt {
                    Text(checkedAt, style: .relative)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                }
            }
            .foregroundStyle(tint)
            .lineLimit(1)

            if let message = state.message {
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.86))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    private var tint: Color {
        switch state.kind {
        case .notValidated:
            palette.tertiaryText
        case .checking:
            palette.brown
        case .valid:
            palette.green
        case .invalid:
            .red
        }
    }
}
