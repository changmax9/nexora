import AppKit
import ClashGlassCore
import Sparkle
import SwiftUI

@main
struct ClashGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared

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
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    let systemAppearanceMonitor = SystemAppearanceMonitor()
    private var windowActivationAttempts = 0
    private var menuBarPanelController: MenuBarPanelController?
    private var updateAccessoryController: NSTitlebarAccessoryViewController?
    private var hasPendingUpdateReminder = false
    private var isManualUpdateProbeInProgress = false
    private var manualProbeResolved = false
    private var pendingScheduledUpdateVersion: String?
    private var wakeObserver: NSObjectProtocol?
    private var automationCatalogObserver: NSObjectProtocol?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
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
            store.onCheckForUpdatesRequested = { [weak self] in
                self?.beginManualUpdateCheck()
            }
            store.onInstallUpdateRequested = { [weak self] in
                self?.launchSparkleInteractiveUpdate()
            }
            _ = updaterController
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AppStore.shared
        store?.recoverSystemProxyAfterRelaunch()
        NexoraAppShortcuts.updateAppShortcutParameters()
        automationCatalogObserver = NotificationCenter.default.addObserver(
            forName: AutomationProxyNode.catalogDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NexoraAppShortcuts.updateAppShortcutParameters() }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureWindowsWhenReady()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.store?.resumeRuntimeAfterWake() }
            Task { @MainActor [weak self] in await self?.store?.checkForAnnouncement() }
        }
        // A local installer can reconnect without depending on a live chat or
        // UI automation after replacing a running VPN client.
        if ProcessInfo.processInfo.arguments.contains("--connect") {
            Task { @MainActor [weak self] in
                guard let store = self?.store else { return }
                do {
                    try await store.setConnectionEnabledForAutomation(true)
                } catch {
                    store.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.shutdownForApplicationTermination() == false ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let automationCatalogObserver { NotificationCenter.default.removeObserver(automationCatalogObserver) }
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
                // Let AppKit place the traffic lights within a full-height title area.
                if window.toolbar == nil {
                    let toolbar = NSToolbar(identifier: "NexoraWindowChrome")
                    toolbar.allowsUserCustomization = false
                    window.toolbar = toolbar
                }
                window.toolbarStyle = .unified
                window.titlebarSeparatorStyle = .none
                window.isOpaque = false
                window.backgroundColor = .clear
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

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // A window can host our gentle reminder; otherwise Sparkle must keep
        // the update discoverable while Nexora is only running in the menu bar.
        store == nil || !NSApp.windows.contains { $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) }
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
            pendingScheduledUpdateVersion = update.displayVersionString
            hasPendingUpdateReminder = true
            showUpdateAccessory()
        } else {
            hasPendingUpdateReminder = false
            removeUpdateAccessory()
            if !handleShowingUpdate {
                // Downloaded updates still need Sparkle's ready-to-install UI.
                // A user-initiated check always hands presentation to Sparkle.
                DispatchQueue.main.async { [weak self] in
                    self?.updaterController.checkForUpdates(nil)
                }
            }
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingScheduledUpdateVersion = nil
        hasPendingUpdateReminder = false
        removeUpdateAccessory()
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var currentAppBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private func beginManualUpdateCheck() {
        if let pendingVersion = pendingScheduledUpdateVersion {
            store?.finishManualUpdateCheck(.updateAvailable(
                currentVersion: currentAppVersion,
                latestVersion: pendingVersion
            ))
            return
        }
        let updater = updaterController.updater
        if updater.sessionInProgress {
            if updater.canCheckForUpdates {
                store?.cancelManualUpdateCheck()
                updaterController.checkForUpdates(nil)
            } else {
                store?.finishManualUpdateCheck(.failed(
                    message: store?.text(.updateCheckUnavailable) ?? "Update checks are currently unavailable."
                ))
            }
            return
        }
        isManualUpdateProbeInProgress = true
        manualProbeResolved = false
        updater.checkForUpdateInformation()
    }

    private func launchSparkleInteractiveUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard isManualUpdateProbeInProgress else { return }
        manualProbeResolved = true
        isManualUpdateProbeInProgress = false
        store?.finishManualUpdateCheck(.updateAvailable(
            currentVersion: currentAppVersion,
            latestVersion: item.displayVersionString
        ))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        guard isManualUpdateProbeInProgress else { return }
        manualProbeResolved = true
        isManualUpdateProbeInProgress = false
        let nsError = error as NSError
        let reason = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)
            .flatMap { SPUNoUpdateFoundReason(rawValue: OSStatus($0.int32Value)) }
        switch reason {
        case .onLatestVersion, .onNewerThanLatestVersion:
            store?.finishManualUpdateCheck(.upToDate(currentVersion: currentAppVersion))
        case .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64:
            store?.finishManualUpdateCheck(.failed(message: error.localizedDescription))
        case .unknown, .none:
            if let latestItem = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem,
               let currentBuild = currentAppBuild,
               SUStandardVersionComparator.default.compareVersion(
                   currentBuild,
                   toVersion: latestItem.versionString
               ) == .orderedAscending {
                store?.finishManualUpdateCheck(.updateAvailable(
                    currentVersion: currentAppVersion,
                    latestVersion: latestItem.displayVersionString
                ))
            } else {
                store?.finishManualUpdateCheck(.upToDate(currentVersion: currentAppVersion))
            }
        @unknown default:
            store?.finishManualUpdateCheck(.upToDate(currentVersion: currentAppVersion))
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard isManualUpdateProbeInProgress, !manualProbeResolved else { return }
        manualProbeResolved = true
        isManualUpdateProbeInProgress = false
        if let error {
            let nsError = error as NSError
            if nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue) {
                store?.finishManualUpdateCheck(.upToDate(currentVersion: currentAppVersion))
            } else {
                store?.finishManualUpdateCheck(.failed(message: error.localizedDescription))
            }
        } else {
            store?.finishManualUpdateCheck(.upToDate(currentVersion: currentAppVersion))
        }
    }

    private func showUpdateAccessory() {
        guard updateAccessoryController == nil, let store else {
            return
        }
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
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
