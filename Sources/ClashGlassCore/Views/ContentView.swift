import SwiftUI

public struct ContentView: View {
    @Bindable private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        let accent = store.accent.color(for: colorScheme)
        let palette = GlassPalette(colorScheme: colorScheme, accent: accent)
        GeometryReader { geometry in
            let layout = AppChromeLayoutMetrics(
                availableWidth: Double(geometry.size.width),
                availableHeight: Double(geometry.size.height)
            )

            ZStack {
                palette.background.ignoresSafeArea()

                HStack(spacing: 0) {
                    IconRail(store: store)
                        .frame(width: CGFloat(layout.railWidth))
                        .background(palette.background)
                        .zIndex(RailSurfaceMetrics.railZIndex)

                    MainStage(store: store, layout: layout)
                        .zIndex(RailSurfaceMetrics.stageZIndex)
                }
            }
        }
        .foregroundStyle(palette.primaryText)
        .tint(accent)
        .accentColor(accent)
        .environment(
            \.clashGlassReduceMotion,
            AppMotionPolicy.reducesMotion(
                systemPreference: accessibilityReduceMotion,
                appPreference: store.reduceMotion
            )
        )
        .containerBackground(palette.background, for: .window)
        .alert(
            "Nexora",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            )
        ) {
            Button(store.text(.ok)) {
                store.lastErrorMessage = nil
            }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
        .task {
            await store.refreshNetworkIdentity()
            while !Task.isCancelled {
                await store.runtimeTick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

private struct IconRail: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var hoverState = RailHoverState()

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        VStack(spacing: CGFloat(RailLayoutMetrics.itemSpacing)) {
            ForEach(AppSection.allCases) { section in
                let item = RailItem.section(section)
                let presentation = RailItemPresentation(
                    item: item,
                    selectedSection: store.selectedSection,
                    hoveredItem: hoverState.hoveredItem
                )

                Button {
                    store.selectedSection = section
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            presentation.emphasizesIcon
                                ? palette.primaryText
                                : palette.secondaryText
                        )
                        .animation(
                            RailSelectionMotion.animation(reduceMotion: reduceMotion),
                            value: presentation.emphasizesIcon
                        )
                        .frame(
                            width: CGFloat(RailHitTargetMetrics.width),
                            height: CGFloat(RailHitTargetMetrics.height)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoverState.update(item: item, isHovering: hovering)
                }
                .help(store.text(section.titleKey))
            }

            Spacer()
        }
        .background(alignment: .top) {
            // Keep one surface alive so interrupted selections only retarget its position.
            railSelection(palette: palette)
                .frame(
                    width: CGFloat(RailLayoutMetrics.selectionWidth),
                    height: CGFloat(RailLayoutMetrics.selectionHeight)
                )
                .frame(
                    width: CGFloat(RailHitTargetMetrics.width),
                    height: CGFloat(RailHitTargetMetrics.height)
                )
                .offset(y: CGFloat(RailLayoutMetrics.selectionOffset(for: store.selectedSection)))
                .animation(
                    RailSelectionMotion.animation(reduceMotion: reduceMotion),
                    value: store.selectedSection
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.top, CGFloat(RailLayoutMetrics.topInset))
    }

    @ViewBuilder
    private func railSelection(palette: GlassPalette) -> some View {
        Capsule(style: .continuous)
            .fill(palette.railSelection)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(palette.selectionStroke.opacity(0.52), lineWidth: 0.8)
            }
            .shadow(
                color: palette.shadow.opacity(0.075),
                radius: RailSurfaceMetrics.selectionShadowRadius,
                y: 3
            )
    }
}

private struct MainStage: View {
    @Bindable var store: AppStore
    let layout: AppChromeLayoutMetrics
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clashGlassReduceMotion) private var reduceMotion
    @State private var showsCoreRestartConfirmation = false
    @State private var showsProfileRename = false
    @State private var renameProfileID: ManagedProfile.ID?
    @State private var renameDraft = ""
    @State private var isQuickEditHovering = false

    var body: some View {
        let palette = GlassPalette(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: CGFloat(MainStageLayoutMetrics.toolbarToContentSpacing)) {
            HStack(alignment: .center) {
                ZStack(alignment: .leading) {
                    Text(store.text(store.selectedSection.titleKey))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .id(store.selectedSection)
                        .transition(.opacity)
                }
                .animation(
                    PageNavigationTransitionPolicy.animation(reduceMotion: reduceMotion),
                    value: store.selectedSection
                )

                Spacer()

                HStack(spacing: 10) {
                    LiquidIconButton(
                        title: store.isStarted ? store.text(.pause) : store.text(.start),
                        symbol: store.isStarted ? "pause.fill" : "play.fill",
                        tint: palette.rose.opacity(0.48),
                        size: CGFloat(ToolbarControlMetrics.visibleSize)
                    ) {
                        Task {
                            await store.toggleRuntime(configPath: store.configPath)
                        }
                    }
                    .disabled(store.isRuntimeTransitioning)

                    CoreStatusToolbarButton(
                        symbol: coreStatusSymbol,
                        isRunning: store.isCoreRunning,
                        accessibilityTitle: store.text(.coreStatus)
                    ) {
                        showsCoreRestartConfirmation = true
                    }
                    .disabled(store.isRuntimeTransitioning)

                    ZStack {
                        ToolbarMenuIconSurface(
                            symbol: ToolbarControlAppearancePolicy.quickEditSymbol,
                            isHovering: isQuickEditHovering
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        AppKitMenuButton(entries: [
                            .item(
                                store.text(.renameProfile),
                                symbol: "pencil",
                                isEnabled: store.selectedManagedProfile != nil
                            ) {
                                beginRenamingSelectedProfile()
                            },
                            .item(
                                store.text(.validate),
                                symbol: "checkmark.shield",
                                isEnabled: store.selectedManagedProfile != nil
                            ) {
                                guard let profileID = store.selectedManagedProfileID else {
                                    return
                                }
                                Task {
                                    await store.validateManagedProfile(profileID)
                                }
                            },
                            .item(
                                store.text(.revealInFinder),
                                symbol: "folder",
                                isEnabled: store.selectedManagedProfile != nil
                            ) {
                                guard let profile = store.selectedManagedProfile else {
                                    return
                                }
                                ConfigurationFilePanel.reveal(profile.managedConfigURL)
                            },
                            .separator,
                            .item(
                                store.text(.routing),
                                symbol: "point.3.connected.trianglepath.dotted"
                            ) {
                                store.selectedSection = .routing
                            },
                            .item(
                                store.text(.profiles),
                                symbol: "folder.fill"
                            ) {
                                store.selectedSection = .profiles
                            },
                        ], accessibilityTitle: store.text(.quickEdit))
                        .frame(
                            width: CGFloat(ToolbarControlMetrics.hitTarget),
                            height: CGFloat(ToolbarControlMetrics.hitTarget)
                        )
                    }
                    .frame(
                        width: CGFloat(ToolbarControlMetrics.hitTarget),
                        height: CGFloat(ToolbarControlMetrics.hitTarget)
                    )
                    .help(store.text(.quickEdit))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(store.text(.quickEdit))
                    .onHover { isQuickEditHovering = $0 }
                }
            }
            .frame(
                width: CGFloat(layout.stageWidth),
                height: CGFloat(MainStageLayoutMetrics.toolbarHeight)
            )

            selectedSectionContent
                .frame(
                    width: CGFloat(layout.stageWidth),
                    height: CGFloat(MainStageLayoutMetrics.contentHeight(stageHeight: layout.stageHeight)),
                    alignment: .topLeading
                )

            Spacer(minLength: 0)
        }
        .padding(.top, CGFloat(layout.topInset))
        .padding(.leading, CGFloat(layout.contentLeadingInset))
        .padding(.trailing, CGFloat(layout.contentTrailingInset))
        .confirmationDialog(
            store.isCoreRunning ? store.text(.restartCore) : store.text(.startCore),
            isPresented: $showsCoreRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button(store.isCoreRunning ? store.text(.restartCore) : store.text(.startCore)) {
                Task {
                    await store.restartCore()
                }
            }
            Button(store.text(.cancel), role: .cancel) {}
        } message: {
            Text(coreRestartMessage)
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
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch store.selectedSection {
        case .dashboard:
            DashboardView(store: store, availableWidth: layout.stageWidth)
        case .diagnostics:
            DiagnosticsView(store: store)
        case .proxies:
            ProxiesView(store: store)
        case .routing:
            RoutingView(store: store)
        case .profiles:
            ProfilesView(store: store)
        case .connections:
            ConnectionsView(store: store)
        case .settings:
            AppSettingsView(store: store)
        }
    }

    private var coreStatusSymbol: String {
        store.isCoreRunning
            ? ToolbarControlAppearancePolicy.runningCoreSymbol
            : ToolbarControlAppearancePolicy.stoppedCoreSymbol
    }

    private var coreRestartMessage: String {
        if store.isStarted {
            return store.text(.restartActiveExplanation)
        }
        if store.isCoreRunning {
            return store.text(.restartControllerExplanation)
        }
        return store.text(.startControllerExplanation)
    }

    private func beginRenamingSelectedProfile() {
        guard let profile = store.selectedManagedProfile else {
            return
        }
        renameProfileID = profile.id
        renameDraft = profile.name
        showsProfileRename = true
    }
}
