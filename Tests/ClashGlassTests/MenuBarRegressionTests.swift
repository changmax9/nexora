import Foundation
import Testing
@testable import ClashGlassCore

@MainActor
@Test func menuBarResolvesRenamedSelectorsAndGlobalMode() {
    let store = AppStore()
    let alpha = ProxyNode(name: "Alpha", region: "SG", latency: 24, isSelected: true)
    let beta = ProxyNode(name: "Beta", region: "JP", latency: 60, isSelected: false)
    store.proxyGroups = [
        ProxyGroup(name: "GLOBAL", policy: "Selector", kind: .selector, nodes: [
            ProxyNode(name: "My Routes", region: "", latency: nil, isSelected: true, isGroup: true),
            alpha, beta
        ]),
        ProxyGroup(name: "My Routes", policy: "Selector", kind: .selector, nodes: [alpha, beta]),
        ProxyGroup(name: "Streaming", policy: "Selector", kind: .selector, nodes: [beta])
    ]
    #expect(store.menuBarSelector?.name == "My Routes")
    #expect(store.menuBarSelectedNodeName == "Alpha")
    #expect(store.menuBarProxyNodes.count == 2)
    store.selectedMode = .global
    #expect(store.menuBarSelector?.name == "GLOBAL")
    store.menuBarPreferredGroupName = "Streaming"
    #expect(store.menuBarSelector?.name == "Streaming")
    store.menuBarPreferredGroupName = "Deleted Group"
    #expect(store.menuBarSelector?.name == "GLOBAL")
}

@MainActor
@Test func emptyProxySnapshotClearsStaleNodesAndSelections() {
    let store = AppStore()
    store.proxyGroups = [ProxyGroup(name: "Old profile", policy: "Selector", kind: .selector, nodes: [
        ProxyNode(name: "Old node", region: "", latency: nil, isSelected: true)
    ])]
    store.applyProxyResponse(Data(#"{"proxies":{}}"#.utf8))
    #expect(store.proxyGroups.isEmpty)
    #expect(store.menuBarProxyNodes.isEmpty)
    #expect(store.menuBarSelectedNodeName == nil)
}

@Test func menuPanelStaysInsideTheStatusItemsScreen() {
    let secondary = CGRect(x: -1280, y: -300, width: 1280, height: 700)
    let size = CGSize(width: 360, height: 540)
    let origin = MenuBarPanelPlacement.origin(
        panelSize: size,
        statusFrame: CGRect(x: -35, y: 400, width: 24, height: 24),
        visibleFrame: secondary
    )
    #expect(secondary.contains(CGRect(origin: origin, size: size)))
    let lowerOrigin = MenuBarPanelPlacement.origin(
        panelSize: size,
        statusFrame: CGRect(x: -1270, y: -100, width: 24, height: 24),
        visibleFrame: secondary
    )
    #expect(secondary.contains(CGRect(origin: lowerOrigin, size: size)))
}
