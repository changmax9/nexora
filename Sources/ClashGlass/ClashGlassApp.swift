import AppKit
import ClashGlassCore
import Sparkle
import SwiftUI

@main
struct ClashGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Nexora", id: "main") {
            ContentView(store: store)
                .preferredColorScheme(
                    store.appearanceMode.resolvedColorScheme(
                        systemColorScheme: appDelegate.systemAppearanceMonitor.colorScheme
                    )
                )
                .environment(\.locale, store.language.locale)
                .task {
                    appDelegate.store = store
                    if let section = ProcessInfo.processInfo.environment["CLASH_GLASS_SECTION"],
                       let selected = AppSection(rawValue: section) {
                        store.selectedSection = selected
                    }
                }
                .frame(
                    minWidth: CGFloat(MainWindowLayoutMetrics.minimumWidth),
                    minHeight: CGFloat(MainWindowLayoutMetrics.minimumHeight)
                )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: CGFloat(MainWindowLayoutMetrics.defaultWidth),
            height: CGFloat(MainWindowLayoutMetrics.defaultHeight)
        )
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button(store.text(.menuQuickAccess)) {
                    appDelegate.toggleQuickAccess()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    let systemAppearanceMonitor = SystemAppearanceMonitor()
    private var windowActivationAttempts = 0
    private var menuBarPanelController: MenuBarPanelController?
    private var updateAccessoryController: NSTitlebarAccessoryViewController?
    private var hasPendingUpdateReminder = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    var store: AppStore? {
        didSet {
            guard menuBarPanelController == nil, let store else {
                return
            }
            menuBarPanelController = MenuBarPanelController(
                store: store,
                systemAppearanceMonitor: systemAppearanceMonitor
            )
            _ = updaterController
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureWindowsWhenReady()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdownForApplicationTermination()
    }

    func toggleQuickAccess() {
        menuBarPanelController?.togglePanel()
    }

    private func configureWindowsWhenReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let windows = NSApp.windows.filter { window in
                window.canBecomeKey && !(window is NSPanel)
            }

            guard !windows.isEmpty else {
                windowActivationAttempts += 1
                if windowActivationAttempts < 20 {
                    configureWindowsWhenReady()
                }
                return
            }

            for window in windows {
                let contentSize = window.contentLayoutRect.size
                window.contentMinSize = NSSize(
                    width: CGFloat(MainWindowLayoutMetrics.minimumWidth),
                    height: CGFloat(MainWindowLayoutMetrics.minimumHeight)
                )
                if MainWindowLayoutMetrics.needsLaunchExpansion(
                    width: Double(contentSize.width),
                    height: Double(contentSize.height)
                ) {
                    window.setContentSize(NSSize(
                        width: CGFloat(MainWindowLayoutMetrics.defaultWidth),
                        height: CGFloat(MainWindowLayoutMetrics.defaultHeight)
                    ))
                    window.center()
                }
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.titleVisibility = .hidden
                window.toolbarStyle = .unifiedCompact
                window.backgroundColor = NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? .black
                        : .white
                }
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
            if hasPendingUpdateReminder {
                showUpdateAccessory()
            }
            if ProcessInfo.processInfo.environment["CLASH_GLASS_PREVIEW_UPDATE"] == "1" {
                showUpdateAccessory()
            }
            NSRunningApplication.current.activate(options: .activateAllWindows)
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if UpdateReminderPolicy.shouldShowCapsule(
            standardDriverWillShowUpdate: handleShowingUpdate,
            updateIsNotDownloaded: state.stage == .notDownloaded
        ) {
            hasPendingUpdateReminder = true
            showUpdateAccessory()
        } else {
            hasPendingUpdateReminder = false
            removeUpdateAccessory()
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        hasPendingUpdateReminder = false
        removeUpdateAccessory()
    }

    private func showUpdateAccessory() {
        guard updateAccessoryController == nil, let store else {
            return
        }
        guard let window = NSApp.windows.first(where: {
            $0.canBecomeKey && !($0 is NSPanel)
        }) else {
            return
        }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        let hostingView = NSHostingView(
            rootView: UpdateTitlebarCapsule(store: store) { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            }
        )
        hostingView.frame.size = hostingView.fittingSize
        accessory.view = hostingView
        window.addTitlebarAccessoryViewController(accessory)
        updateAccessoryController = accessory
    }

    private func removeUpdateAccessory() {
        guard let updateAccessoryController else {
            return
        }
        if let window = updateAccessoryController.view.window,
           let index = window.titlebarAccessoryViewControllers.firstIndex(
               where: { $0 === updateAccessoryController }
           ) {
            window.removeTitlebarAccessoryViewController(at: index)
        } else {
            updateAccessoryController.view.removeFromSuperview()
        }
        self.updateAccessoryController = nil
    }
}

private struct UpdateTitlebarCapsule: View {
    @Bindable var store: AppStore
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text(store.text(.update))
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 11)
            .frame(height: 25)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.primary.opacity(isHovering ? 0.20 : 0.10))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75),
            value: isHovering
        )
        .padding(.leading, 4)
        .padding(.vertical, 3)
        .help(store.text(.update))
    }

    private var reduceMotion: Bool {
        AppMotionPolicy.reducesMotion(
            systemPreference: accessibilityReduceMotion,
            appPreference: store.reduceMotion
        )
    }
}
