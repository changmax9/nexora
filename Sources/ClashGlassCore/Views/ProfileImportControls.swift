import SwiftUI

struct ProfileImportButton: View {
    let store: AppStore
    @State private var showsMenu = false
    @State private var showsURLImport = false
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        menuButton
        .popover(isPresented: $showsMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.text(.importConfiguration))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                GlassActionPopoverRow(
                    title: store.text(.importFromFile),
                    symbol: "doc.badge.plus",
                    isEnabled: true,
                    subtitle: store.text(.importFileHint)
                ) {
                    showsMenu = false
                    guard let url = ConfigurationFilePanel.chooseYAML() else { return }
                    Task { await store.importManagedProfile(from: url) }
                }
                GlassActionPopoverRow(
                    title: store.text(.importFromURL),
                    symbol: "link",
                    isEnabled: true,
                    subtitle: store.text(.importURLHint)
                ) {
                    showsMenu = false
                    showsURLImport = true
                }
            }
            .padding(8)
            .frame(width: 288)
            .tint(store.accent.color(for: colorScheme))
            .accentColor(store.accent.color(for: colorScheme))
            .environment(\.clashGlassReduceMotion, reduceMotion)
            .onKeyPress(.escape) { showsMenu = false; return .handled }
        }
        .sheet(isPresented: $showsURLImport) {
            ProfileURLImportSheet(store: store)
                .tint(store.accent.color(for: colorScheme))
                .accentColor(store.accent.color(for: colorScheme))
        }
    }

    private var menuButton: some View {
        LiquidIconButton(title: store.text(.importConfiguration), symbol: "plus", size: 32) {
            showsMenu.toggle()
        }
    }
}

private struct ProfileURLImportSheet: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlDraft = ""
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    @FocusState private var isURLFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 12) { sheetContent }
            } else {
                sheetContent
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(isImporting)
        .onAppear { isURLFocused = true }
        .onChange(of: urlDraft) { errorMessage = nil }
        .onDisappear { importTask?.cancel() }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.text(.importFromURL))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(store.text(.importURLHint))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.text(.profileURL))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                TextField("https://example.com/config.yaml", text: $urlDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .modifier(ProfileImportFieldSurface())
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isURLFocused ? Color.accentColor.opacity(0.6) : .clear,
                                lineWidth: 1.5
                            )
                            .allowsHitTesting(false)
                    }
                    .focused($isURLFocused)
                    .disabled(isImporting)
                    .accessibilityLabel(store.text(.profileURL))
                    .onSubmit { startImport() }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                if isImporting {
                    ProgressView().controlSize(.small)
                    Text(store.text(.importingProfile))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                importActions
            }
        }
    }

    private var importActions: some View {
        HStack(spacing: 10) {
            cancelButton.buttonStyle(LiquidGlassButtonStyle(radius: 12))
            downloadButton
                .buttonStyle(LiquidGlassButtonStyle(
                    radius: 12,
                    tint: canImport ? store.accent.color(for: colorScheme).opacity(0.25) : nil
                ))
                .opacity(canImport ? 1 : 0.45)
        }
        .foregroundStyle(GlassPalette(colorScheme: colorScheme).primaryText)
    }

    private var cancelButton: some View {
        Button {
            importTask?.cancel()
            dismiss()
        } label: {
            actionLabel(store.text(.cancel))
        }
        .keyboardShortcut(.cancelAction)
    }

    private var downloadButton: some View {
        Button { startImport() } label: {
            actionLabel(store.text(.downloadAndImport))
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canImport)
    }

    private var canImport: Bool {
        !isImporting && !urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func startImport() {
        guard !isImporting else { return }
        let url: URL
        do {
            url = try ManagedProfileDownloader.configurationURL(from: urlDraft)
        } catch {
            errorMessage = store.text(.invalidProfileURL)
            isURLFocused = true
            return
        }

        errorMessage = nil
        isImporting = true
        importTask = Task { @MainActor in
            defer { isImporting = false }
            do {
                _ = try await store.importManagedProfile(fromRemoteURL: url)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? ManagedProfileDownloadError)?.message(language: store.language)
                    ?? error.localizedDescription
                isURLFocused = true
            }
        }
    }
}

private struct ProfileImportFieldSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if reduceTransparency {
            content.background(.background, in: shape)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(!reduceMotion), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
