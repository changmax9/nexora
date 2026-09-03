import SwiftUI

enum PageSurfaceMetrics {
    static let horizontalInset: CGFloat = 28
    static let topInset: CGFloat = 28

    static func contentWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - horizontalInset * 2)
    }
}

enum FeatureToolbarLayoutMetrics {
    static let searchWidth: CGFloat = 280
    static let customLeadingWidth: CGFloat = 560
    static let actionSpacing: CGFloat = 10
    static let minimumGap: CGFloat = 12
    static let compactRowSpacing: CGFloat = 10

    static func actionsWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * CGFloat(ToolbarControlMetrics.hitTarget)
            + CGFloat(count - 1) * actionSpacing
    }

    static func requiredHorizontalWidth(leadingWidth: CGFloat, actionCount: Int) -> CGFloat {
        leadingWidth + (actionCount > 0 ? minimumGap : 0) + actionsWidth(count: actionCount)
    }
}

struct FeaturePage<Content: View>: View {
    var searchText: Binding<String>? = nil
    var toolbarLeading: AnyView? = nil
    let placeholder: String
    let actions: [FeatureAction]
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureToolbar
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.horizontal, PageSurfaceMetrics.horizontalInset)

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    content
                        .frame(
                            width: PageSurfaceMetrics.contentWidth(availableWidth: proxy.size.width),
                            alignment: .topLeading
                        )
                        .padding(.top, PageSurfaceMetrics.topInset)
                        .padding(.horizontal, PageSurfaceMetrics.horizontalInset)
                        .padding(.bottom, 96)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var featureToolbar: some View {
        if toolbarLeading != nil || searchText != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    preferredLeadingControl
                    Spacer(minLength: FeatureToolbarLayoutMetrics.minimumGap)
                    actionButtons
                }

                VStack(alignment: .leading, spacing: FeatureToolbarLayoutMetrics.compactRowSpacing) {
                    flexibleLeadingControl
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        actionButtons
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var preferredLeadingControl: some View {
        if let toolbarLeading {
            toolbarLeading
                .frame(width: FeatureToolbarLayoutMetrics.customLeadingWidth, alignment: .leading)
        } else if let searchText {
            SearchCapsule(text: searchText, placeholder: placeholder)
                .frame(width: FeatureToolbarLayoutMetrics.searchWidth)
        }
    }

    @ViewBuilder
    private var flexibleLeadingControl: some View {
        if let toolbarLeading {
            toolbarLeading
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let searchText {
            SearchCapsule(text: searchText, placeholder: placeholder)
                .frame(maxWidth: FeatureToolbarLayoutMetrics.searchWidth, alignment: .leading)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: FeatureToolbarLayoutMetrics.actionSpacing) {
            ForEach(actions) { action in
                LiquidIconButton(
                    title: action.title,
                    symbol: action.symbol,
                    size: 32,
                    action: action.action
                )
                .disabled(action.isDisabled)
                .opacity(action.isDisabled ? 0.55 : 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct FeatureAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var isDisabled = false
    let action: () -> Void
}

struct SearchCapsule: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background {
            LiquidGlassSurface(radius: 16, padding: 0) {
                Color.clear
            }
        }
    }
}

struct PillSegment<Value: Hashable & Identifiable>: View where Value.ID == Value {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @State private var hoveredValue: Value?

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 4) {
            ForEach(values) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78)) {
                        selection = value
                    }
                } label: {
                    Text(title(value))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selection == value ? palette.brown : palette.secondaryText)
                        .frame(height: 26)
                        .padding(.horizontal, 10)
                        .background {
                            if selection == value {
                                selectedSurface
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            } else if hoveredValue == value {
                                Capsule(style: .continuous)
                                    .fill(palette.selectionHover)
                            }
                        }
                }
                .buttonStyle(.plain)
                .scaleEffect(hoveredValue == value ? 1.025 : 1)
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.76)) {
                        hoveredValue = hovering ? value : nil
                    }
                }
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(palette.selectionTrack)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.selectionStroke.opacity(0.48), lineWidth: 0.8)
                }
        }
    }

    private var selectedSurface: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        return Capsule(style: .continuous)
            .fill(palette.selectionFill)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(palette.selectionStroke, lineWidth: 0.8)
            }
    }
}

struct StatusChip: View {
    let text: String
    let symbol: String?
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .foregroundStyle(tint ?? .secondary)
        .background((tint ?? Color.secondary).opacity(0.12), in: Capsule(style: .continuous))
    }
}

struct EmptyGlassState: View {
    let title: String
    let symbol: String

    var body: some View {
        GlassCard(radius: 16, padding: 26) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }
}
