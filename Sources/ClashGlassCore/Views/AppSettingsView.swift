import SwiftUI

public struct AppSettingsView: View {
    @Bindable private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isLatencyTestURLFocused: Bool
    @State private var latencyTestURLDraft: String

    public init(store: AppStore) {
        self.store = store
        _latencyTestURLDraft = State(initialValue: store.latencyTestURL)
    }

    public var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.text(.settings))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(store.text(.settingsSubtitle))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                appearanceSettings
                languageSettings
                latencySettings
                aboutSettings
            }
            .padding(PageSurfaceMetrics.horizontalInset)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(palette.primaryText)
        .background(palette.background)
        .environment(\.locale, store.language.locale)
    }

    private var appearanceSettings: some View {
        SettingsGroup(title: store.text(.appearance), symbol: "paintbrush") {
            VStack(spacing: 0) {
                HStack {
                    Text(store.text(.colorScheme))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    PillSegment(
                        values: AppAppearance.allCases,
                        selection: $store.appearanceMode
                    ) { appearanceTitle($0) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().opacity(0.12)

                AccentColorPicker(
                    title: store.text(.accentColor),
                    selectedTitle: store.text(.selected),
                    selection: $store.accent
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().opacity(0.12)

                HStack {
                    Text(store.text(.reduceMotion))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    LiquidToggle(isOn: store.reduceMotion) {
                        store.reduceMotion.toggle()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
    }

    private var latencySettings: some View {
        SettingsGroup(title: store.text(.latencyTesting), symbol: "speedometer") {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(store.text(.latencyTestURL))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    TextField(LatencyTestPlan.defaultTestURL, text: $latencyTestURLDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .focused($isLatencyTestURLFocused)
                        .onSubmit(commitLatencyTestURL)
                        .onChange(of: isLatencyTestURLFocused) { _, isFocused in
                            if !isFocused {
                                commitLatencyTestURL()
                            }
                        }
                        .frame(maxWidth: 360)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().opacity(0.12)

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(store.text(.latencyTestTimeout))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Stepper(
                        value: $store.latencyTestTimeoutMilliseconds,
                        in: LatencyTestSettings.minimumTimeoutMilliseconds...LatencyTestSettings.maximumTimeoutMilliseconds,
                        step: 500
                    ) {
                        Text("\(store.latencyTestTimeoutMilliseconds) ms")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
        .onAppear {
            latencyTestURLDraft = store.latencyTestURL
        }
        .onDisappear(perform: commitLatencyTestURL)
    }

    private var languageSettings: some View {
        SettingsGroup(title: store.text(.language), symbol: "globe") {
            HStack {
                Text(store.text(.language))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Picker("", selection: $store.language) {
                    ForEach(AppLanguage.selectableCases) { language in
                        Text(language.nativeDisplayName)
                            .tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
    }

    private var aboutSettings: some View {
        VStack(spacing: 14) {
            SettingsGroup(title: store.text(.about), symbol: "info.circle") {
                SettingsValueRow(title: store.text(.version), value: appVersion)
                SettingsValueRow(
                    title: store.text(.engine),
                    value: store.text(.poweredByMihomo)
                )
            }

            SettingsGroup(title: store.text(.legalNotice), symbol: "exclamationmark.shield") {
                SettingsLegalNotice(
                    title: store.text(.permittedUse),
                    text: store.text(.disclaimerPurpose)
                )
                SettingsLegalNotice(
                    title: store.text(.yourResponsibility),
                    text: store.text(.disclaimerResponsibility)
                )
                SettingsLegalNotice(
                    title: store.text(.noWarranty),
                    text: store.text(.disclaimerLiability)
                )
                SettingsLegalNotice(
                    title: store.text(.thirdPartyServices),
                    text: store.text(.disclaimerThirdParties)
                )
                SettingsLegalNotice(
                    title: store.text(.indemnification),
                    text: store.text(.disclaimerIndemnity)
                )
            }
        }
    }

    private func appearanceTitle(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: store.text(.system)
        case .light: store.text(.light)
        case .dark: store.text(.dark)
        }
    }

    private func commitLatencyTestURL() {
        store.latencyTestURL = latencyTestURLDraft
        latencyTestURLDraft = store.latencyTestURL
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }
}

private struct AccentColorPicker: View {
    let title: String
    let selectedTitle: String
    @Binding var selection: NexoraAccent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text(selection.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
            }

            HStack(spacing: 8) {
                ForEach(NexoraAccent.allCases) { accent in
                    let isSelected = accent == selection
                    let swatch = accent.color(for: colorScheme)
                    Button {
                        selection = accent
                    } label: {
                        ZStack {
                            Circle()
                                .fill(swatch)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            }
                        }
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    isSelected ? palette.primaryText : palette.cardStroke,
                                    lineWidth: isSelected ? 1.8 : 0.8
                                )
                        }
                        .scaleEffect(isSelected ? 1 : 0.94)
                    }
                    .buttonStyle(.plain)
                    .help(accent.title)
                    .accessibilityLabel(accent.title)
                    .accessibilityValue(isSelected ? selectedTitle : "")
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.16),
                        value: isSelected
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        GlassCard(radius: 16, padding: 0) {
            VStack(spacing: 0) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider().opacity(0.12)
                content
            }
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct SettingsLegalNotice: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
