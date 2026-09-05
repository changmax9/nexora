import AppKit
import ClashGlassCore
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class MenuBarPanelController: NSObject {
    private let store: AppStore
    private let systemAppearanceMonitor: SystemAppearanceMonitor
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanelWindow
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var panelRefreshTask: Task<Void, Never>?
    private var fadeGeneration = 0
    private var isPresented = false

    private var reducesMotion: Bool {
        AppMotionPolicy.reducesMotion(
            systemPreference: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            appPreference: store.reduceMotion
        )
    }

    init(
        store: AppStore,
        systemAppearanceMonitor: SystemAppearanceMonitor
    ) {
        self.store = store
        self.systemAppearanceMonitor = systemAppearanceMonitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let rootView = MenuBarPanelRootView(
            store: store,
            systemAppearanceMonitor: systemAppearanceMonitor
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame.size = hostingView.fittingSize
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 22
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        panel = MenuBarPanelWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.alphaValue = 0
        panel.onCancel = { [weak self] in self?.hide() }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = "Nexora"
        }

        updateStatusIcon()
        observeStore()
        installDismissMonitors()
    }

    @objc
    func togglePanel() {
        if isPresented {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            return
        }

        fadeGeneration += 1
        isPresented = true
        let generation = fadeGeneration
        let statusFrame = buttonWindow.convertToScreen(button.frame)
        positionPanel(below: statusFrame)

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        // Opening the panel should not begin editing the first text field.
        // Reset this on every presentation, including after a previous search.
        panel.makeFirstResponder(panel)
        refreshPanelSnapshot()

        if reducesMotion {
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = MenuBarPanelMotion.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.fadeGeneration else {
                    return
                }
                self.panel.alphaValue = 1
            }
        }
    }

    private func refreshPanelSnapshot() {
        panelRefreshTask?.cancel()
        panelRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.store.refreshProxies()
            guard !Task.isCancelled else {
                return
            }
            await self.store.refreshNetworkIdentity()
        }
    }

    private func hide() {
        guard isPresented else {
            return
        }
        isPresented = false
        panel.makeFirstResponder(panel)
        panelRefreshTask?.cancel()
        fadeGeneration += 1
        let generation = fadeGeneration

        if reducesMotion {
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = MenuBarPanelMotion.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.fadeGeneration else {
                    return
                }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 0
            }
        }
    }

    private func positionPanel(below statusFrame: NSRect) {
        let panelSize = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(statusFrame) })
            ?? panel.screen
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        panel.setFrameOrigin(MenuBarPanelPlacement.origin(
            panelSize: panelSize, statusFrame: statusFrame, visibleFrame: visibleFrame
        ))
    }

    private func installDismissMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else {
                return event
            }
            if event.window === self.panel || event.window === self.statusItem.button?.window {
                return event
            }
            Task { @MainActor in
                self.hide()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.isStarted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.updateStatusIcon()
                self.observeStore()
            }
        }
    }

    private func updateStatusIcon() {
        statusItem.button?.image = NexoraStatusIcon.image()
        statusItem.button?.toolTip = "Nexora · \(store.text(store.isStarted ? .running : .stopped))"
    }
}

private final class MenuBarPanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let contentView {
            let point = contentView.convert(event.locationInWindow, from: nil)
            var target = contentView.hitTest(point)
            var clickedEditor = false
            while let view = target {
                if view is NSTextField || view is NSTextView {
                    clickedEditor = true
                    break
                }
                target = view.superview
            }
            if !clickedEditor { makeFirstResponder(self) }
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        makeFirstResponder(self)
        super.resignKey()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct MenuBarPanelRootView: View {
    @Bindable var store: AppStore
    @Bindable var systemAppearanceMonitor: SystemAppearanceMonitor

    var body: some View {
        MenuBarPanelView(store: store)
            .preferredColorScheme(
                store.appearanceMode.resolvedColorScheme(
                    systemColorScheme: systemAppearanceMonitor.colorScheme
                )
            )
            .environment(\.locale, store.language.locale)
    }
}
