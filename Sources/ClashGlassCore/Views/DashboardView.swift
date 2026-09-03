import SwiftUI

struct DashboardPageMetrics {
    let availableWidth: CGFloat
    let horizontalInset = PageSurfaceMetrics.horizontalInset

    var contentWidth: CGFloat {
        max(570, PageSurfaceMetrics.contentWidth(availableWidth: availableWidth))
    }
}

struct DashboardView: View {
    @Bindable var store: AppStore
    let availableWidth: Double

    init(store: AppStore, availableWidth: Double = 640) {
        self.store = store
        self.availableWidth = availableWidth
    }

    var body: some View {
        ScrollView(.vertical) {
            glassLayout
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var glassLayout: some View {
        responsiveLayout
            .padding(.top, PageSurfaceMetrics.topInset)
            .padding(.horizontal, PageSurfaceMetrics.horizontalInset)
            .padding(.bottom, 92)
    }

    private var responsiveLayout: some View {
        let contentWidth = DashboardPageMetrics(
            availableWidth: CGFloat(availableWidth)
        ).contentWidth
        let gap = CGFloat(DashboardTopRowLayoutMetrics.gap)
        let rightWidth = max(205, min(260, contentWidth * 0.28))
        let networkWidth = contentWidth - rightWidth - gap
        let columnWidth = (contentWidth - gap * 2) / 3
        let lowerRowHeight = CGFloat(DashboardRowMetrics.standardTotalHeight)
        let topRowHeight = CGFloat(DashboardTopRowLayoutMetrics.networkSpeedHeight)
        let shortHeight = CGFloat(DashboardTopRowLayoutMetrics.toggleCardHeight)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: gap) {
                NetworkSpeedCard(store: store)
                    .frame(width: networkWidth, height: topRowHeight)

                VStack(spacing: gap) {
                    ToggleStatusCard(
                        title: store.text(.systemProxy),
                        optionsTitle: store.text(.options),
                        symbol: "arrow.up.left.and.arrow.down.right",
                        isOn: store.isSystemProxyEnabled
                    ) {
                        Task {
                            await store.toggleSystemProxy()
                        }
                    }
                    .frame(width: rightWidth, height: shortHeight)

                    ToggleStatusCard(
                        title: "TUN",
                        optionsTitle: store.text(.options),
                        symbol: "waveform.path.ecg",
                        isOn: store.isTunEnabled
                    ) {
                        Task {
                            await store.setTunEnabled(!store.isTunEnabled)
                        }
                    }
                    .frame(width: rightWidth, height: shortHeight)
                }
                .frame(width: rightWidth, height: topRowHeight, alignment: .top)
            }
            .frame(height: topRowHeight, alignment: .top)

            HStack(alignment: .top, spacing: 16) {
                DashboardLowerRowCell(
                    width: columnWidth,
                    height: lowerRowHeight
                ) {
                    OutboundModeCard(store: store)
                }

                DashboardLowerRowCell(
                    width: columnWidth,
                    height: lowerRowHeight
                ) {
                    VStack(spacing: 16) {
                        NetworkDetectionCard(store: store)
                            .frame(height: shortHeight, alignment: .top)

                        IntranetIPCard(store: store)
                            .frame(height: shortHeight, alignment: .top)
                    }
                    .frame(
                        width: columnWidth,
                        height: lowerRowHeight,
                        alignment: .top
                    )
                }

                DashboardLowerRowCell(
                    width: columnWidth,
                    height: lowerRowHeight
                ) {
                    TrafficUsageCard(store: store)
                }
            }
            .frame(height: lowerRowHeight, alignment: .top)
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}

private struct DashboardLowerRowCell<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

private struct CardHeader: View {
    let symbol: String
    let title: String
    var trailing: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 17)
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
        .foregroundStyle(palette.secondaryText)
    }
}

private struct NetworkSpeedCard: View {
    @Bindable var store: AppStore

    var body: some View {
        let up = store.isStarted ? store.uploadSpeedText : "0B/s"
        let down = store.isStarted ? store.downloadSpeedText : "0B/s"
        GlassCard(radius: 14, padding: 0) {
            VStack(spacing: 0) {
                CardHeader(symbol: "speedometer", title: store.text(.networkSpeed), trailing: "↑ \(up)   ↓ \(down)")
                    .padding(.horizontal, 16)
                    .padding(.top, 15)

                NetworkCurve(samples: store.isStarted ? store.speedSamples : Array(repeating: 0.0, count: 12))
                    .padding(.top, 8)
            }
        }
    }
}

private struct NetworkCurve: View {
    let samples: [Double]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        Canvas { context, size in
            let values = samples.isEmpty ? [0, 0] : samples
            let maxValue = max(values.max() ?? 1, 1)
            let points = values.enumerated().map { index, value in
                let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let normalized = CGFloat(value / maxValue)
                let y = size.height * (0.83 - normalized * 0.60)
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            line.move(to: points.first ?? CGPoint(x: 0, y: size.height * 0.83))
            for point in points.dropFirst() {
                line.addLine(to: point)
            }

            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [
                        palette.rose.opacity(colorScheme == .dark ? 0.16 : 0.38),
                        palette.brown.opacity(0.04),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(palette.brown.opacity(colorScheme == .dark ? 0.92 : 0.78)), lineWidth: 2.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .linear(duration: 0.45), value: samples)
    }
}

private struct ToggleStatusCard: View {
    let title: String
    let optionsTitle: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        GlassCard(radius: 14, padding: 15) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 15)
                        Text(title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .layoutPriority(1)
                    }
                    Text(optionsTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 2)

                LiquidToggle(isOn: isOn, action: action)
                    .scaleEffect(0.86)
                    .frame(width: 48, height: 30)
            }
        }
    }
}

private struct OutboundModeCard: View {
    @Bindable var store: AppStore

    var body: some View {
        GlassCard(
            radius: 14,
            padding: CGFloat(OutboundModeLayoutMetrics.cardPadding)
        ) {
            VStack(
                alignment: .leading,
                spacing: CGFloat(OutboundModeLayoutMetrics.titleSpacing)
            ) {
                CardHeader(symbol: "arrow.triangle.branch", title: store.text(.outboundMode))
                    .frame(
                        height: CGFloat(OutboundModeLayoutMetrics.headerHeight),
                        alignment: .leading
                    )
                VStack(
                    alignment: .leading,
                    spacing: CGFloat(OutboundModeLayoutMetrics.rowSpacing)
                ) {
                    ForEach(OutboundMode.allCases) { mode in
                        ModeRow(
                            title: store.text(mode.titleKey),
                            mode: mode,
                            selectedMode: store.selectedMode
                        ) {
                            Task {
                                await store.setOutboundMode(mode)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ModeRow: View {
    let title: String
    let mode: OutboundMode
    let selectedMode: OutboundMode
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        let isSelected = selectedMode == mode

        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? palette.selectionFill : Color.clear)
                        .frame(width: 19, height: 19)
                    Circle()
                        .stroke(
                            isSelected ? palette.selectionStroke : palette.secondaryText,
                            lineWidth: 2.2
                        )
                        .frame(width: 19, height: 19)
                    if isSelected {
                        Circle()
                            .fill(palette.brown)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 30, height: 30)
                .scaleEffect(SelectionControlMotion.indicatorScale(
                    isHovering: isHovering,
                    isPressed: false,
                    reduceMotion: reduceMotion
                ))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68),
                    value: isHovering
                )
                .animation(
                    reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78),
                    value: isSelected
                )

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .scaleEffect(SelectionControlMotion.labelScale)

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: ModeRowInteractionPolicy.minimumHitHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct NetworkDetectionCard: View {
    @Bindable var store: AppStore

    var body: some View {
        GlassCard(radius: 14, padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    FlagBadge(countryCode: store.networkCountryCode)
                    Text(store.text(.networkDetection))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 0)
                }
                Text(store.externalIP)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
        }
    }
}

private struct FlagBadge: View {
    let countryCode: String

    var body: some View {
        Text(NetworkIdentity(ip: "", countryCode: countryCode, countryName: "").flagEmoji)
            .font(.system(size: 18))
            .frame(width: 22, height: 16)
    }
}

private struct IntranetIPCard: View {
    @Bindable var store: AppStore

    var body: some View {
        GlassCard(radius: 14, padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(symbol: "rectangle.connected.to.line.below", title: store.text(.intranetIP))
                Text(store.intranetIP)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
        }
    }
}

private struct TrafficUsageCard: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        GlassCard(radius: 14, padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "chart.pie.fill", title: store.text(.trafficUsage))

                HStack(spacing: 14) {
                    DonutView(first: store.isStarted ? 0.35 : 0.5)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 8) {
                        LegendRow(color: palette.rose, title: store.text(.upload))
                        LegendRow(color: palette.tertiaryText.opacity(0.75), title: store.text(.download))
                    }
                }

                VStack(spacing: 8) {
                    TrafficLine(symbol: "arrow.up", value: store.isStarted ? store.uploadTotalText : "0", unit: store.isStarted ? store.uploadTrafficUnit : "B")
                    TrafficLine(symbol: "arrow.down", value: store.isStarted ? store.downloadTotalText : "0", unit: store.isStarted ? store.downloadTrafficUnit : "B")
                }
            }
        }
    }
}

private struct DonutView: View {
    let first: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        ZStack {
            Circle()
                .trim(from: 0.05, to: first)
                .stroke(palette.rose, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: first + 0.08, to: 0.95)
                .stroke(palette.tertiaryText.opacity(0.72), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 20, height: 8)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
    }
}

private struct TrafficLine: View {
    let symbol: String
    let value: String
    let unit: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        HStack {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.tertiaryText)
                .frame(width: 15)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(unit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)
        }
    }
}
