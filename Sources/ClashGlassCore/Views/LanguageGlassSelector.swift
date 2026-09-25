import SwiftUI

struct LanguageGlassSelector: View {
    @Binding var selection: AppLanguage
    let title: String
    let accent: Color
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 10) {
                Text(selection.nativeDisplayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .frame(width: 190, height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(LiquidGlassButtonStyle(radius: 12))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
        .accessibilityLabel(title)
        .accessibilityValue(selection.nativeDisplayName)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            LanguageGlassList(selection: $selection, title: title) { isPresented = false }
                .environment(\.clashGlassReduceMotion, reduceMotion)
                .tint(accent)
                .accentColor(accent)
        }
    }
}

private struct LanguageGlassList: View {
    @Binding var selection: AppLanguage
    let title: String
    let dismiss: () -> Void
    @FocusState private var focusedLanguage: AppLanguage?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "globe")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            ForEach(AppLanguage.selectableCases) { language in
                LanguageGlassRow(language: language, selected: selection == language) {
                    selection = language
                    dismiss()
                }
                .focused($focusedLanguage, equals: language)
            }
        }
        .padding(8)
        .frame(width: 248)
        .onAppear { focusedLanguage = selection }
        .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func moveFocus(by offset: Int) {
        let languages = AppLanguage.selectableCases
        let current = languages.firstIndex(of: focusedLanguage ?? selection) ?? 0
        focusedLanguage = languages[(current + offset + languages.count) % languages.count]
    }
}

private struct LanguageGlassRow: View {
    let language: AppLanguage
    let selected: Bool
    let action: () -> Void
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(language.nativeDisplayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(selected ? 1 : 0)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.07 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering && !reduceMotion ? 1.015 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: isHovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
