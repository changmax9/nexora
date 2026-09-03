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
                .init(title: store.text(.validateAll), symbol: "checkmark.shield") {
                    Task { await store.validateAllManagedProfiles() }
                },
                .init(title: store.text(.openManagedFolder), symbol: "folder") {
                    ConfigurationFilePanel.reveal(store.managedProfilesFolderURL)
                },
                .init(title: store.text(.importYAML), symbol: "plus") {
                    importYAML()
                },
            ]
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
                                    select: {
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
        .dropDestination(for: URL.self) { urls, _ in
            let yamlURLs = urls.filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
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
                store.removeManagedProfile(profilePendingDeletion.id)
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
}

private struct ManagedProfileCard: View {
    let profile: ManagedProfile
    let isSelected: Bool
    let isRunning: Bool
    let validationState: ProfileValidationState
    let language: AppLanguage
    let select: () -> Void
    let validate: () -> Void
    let reveal: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        GlassCard(radius: 16, padding: 16) {
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

                profileActions(palette: palette)
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        }
    }

    private func profileActions(palette: GlassPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ProfileCardActionLayoutMetrics.spacing) {
                selectionButton(palette: palette)
                Spacer(minLength: ProfileCardActionLayoutMetrics.minimumGap)
                secondaryActionButtons(palette: palette)
            }

            VStack(alignment: .leading, spacing: ProfileCardActionLayoutMetrics.spacing) {
                selectionButton(palette: palette)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    secondaryActionButtons(palette: palette)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func selectionButton(palette: GlassPalette) -> some View {
        LiquidActionButton(
            title: isSelected ? language.text(.selected) : language.text(.use),
            symbol: isSelected ? "checkmark" : "play",
            tint: isSelected ? palette.rose.opacity(0.24) : nil,
            compact: true,
            action: select
        )
        .fixedSize(horizontal: true, vertical: false)
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
