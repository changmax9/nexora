import Foundation
import Testing
@testable import ClashGlassCore

@Test func mihomoAPIRequestBuildsGetProxiesEndpoint() throws {
    let request = try MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
        .urlRequest(for: .proxies)

    #expect(request.url?.absoluteString == "http://127.0.0.1:9090/proxies")
    #expect(request.httpMethod == "GET")
}

@Test func mihomoAPIRequestBuildsChangeProxyBody() throws {
    let request = try MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
        .urlRequest(for: .changeProxy(group: "GLOBAL", proxy: "Hong Kong 01"))

    #expect(request.url?.absoluteString == "http://127.0.0.1:9090/proxies/GLOBAL")
    #expect(request.httpMethod == "PUT")
    #expect(String(data: request.httpBody ?? Data(), encoding: .utf8) == "{\"name\":\"Hong Kong 01\"}")
}

@Test func mihomoAPIRequestBuildsDelayTestEndpoint() throws {
    let request = try MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
        .urlRequest(for: .delayTest(proxy: "Hong Kong 01", url: "https://www.gstatic.com/generate_204", timeout: 5000))

    #expect(request.url?.absoluteString == "http://127.0.0.1:9090/proxies/Hong%20Kong%2001/delay?url=https://www.gstatic.com/generate_204&timeout=5000")
    #expect(request.httpMethod == "GET")
}

@Test func mihomoAPIRequestBuildsGroupDelayEndpoint() throws {
    let request = try MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
        .urlRequest(
            for: .groupDelay(
                group: "自动选择 / HK",
                url: "https://www.gstatic.com/generate_204",
                timeout: 5000
            )
        )

    #expect(
        request.url?.absoluteString
            == "http://127.0.0.1:9090/group/%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9%20%2F%20HK/delay?url=https://www.gstatic.com/generate_204&timeout=5000"
    )
    #expect(request.httpMethod == "GET")
}

@Test func mihomoAPIRequestKeepsSlashesInsideProxyNamesEncoded() throws {
    let request = try MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
        .urlRequest(
            for: .delayTest(
                proxy: "防失联网址 https://mutdot.org",
                url: "http://www.gstatic.com/generate_204",
                timeout: 5000
            )
        )

    #expect(request.url?.absoluteString.contains("https:%2F%2Fmutdot.org/delay") == true)
}

@Test func mihomoAPIRequestBuildsRuntimeConfigurationEndpoints() throws {
    let builder = MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)

    let version = try builder.urlRequest(for: .version)
    let configs = try builder.urlRequest(for: .configs)
    let update = try builder.urlRequest(for: .updateConfigs(mode: .global, tunEnabled: true))
    let closeAll = try builder.urlRequest(for: .closeAllConnections)

    #expect(version.url?.absoluteString == "http://127.0.0.1:9090/version")
    #expect(configs.url?.absoluteString == "http://127.0.0.1:9090/configs")
    #expect(update.url?.absoluteString == "http://127.0.0.1:9090/configs")
    #expect(update.httpMethod == "PATCH")
    #expect(closeAll.url?.absoluteString == "http://127.0.0.1:9090/connections")
    #expect(closeAll.httpMethod == "DELETE")

    let body = try #require(update.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["mode"] as? String == "global")
    #expect((json["tun"] as? [String: Any])?["enable"] as? Bool == true)
}

@Test func mihomoAPIDecoderBuildsRuntimeConfiguration() throws {
    let data = """
    {
      "mixed-port": 7890,
      "mode": "rule",
      "tun": {"enable": true}
    }
    """.data(using: .utf8)!

    let config = try MihomoAPIDecoder.runtimeConfig(from: data)

    #expect(config.mixedPort == 7890)
    #expect(config.mode == .rule)
    #expect(config.tunEnabled == true)
}

@Test func mihomoAPIDecoderBuildsProxyGroupsFromMihomoResponse() throws {
    let data = """
    {
      "proxies": {
        "GLOBAL": {"type":"Selector","now":"Tokyo 02","all":["Hong Kong 01","Tokyo 02"]},
        "Hong Kong 01": {"type":"Shadowsocks","history":[{"delay":18}]},
        "Tokyo 02": {"type":"Shadowsocks","history":[{"delay":43}]}
      }
    }
    """.data(using: .utf8)!

    let groups = try MihomoAPIDecoder.proxyGroups(from: data)

    #expect(groups.count == 1)
    #expect(groups[0].name == "GLOBAL")
    #expect(groups[0].nodes.map(\.name) == ["Hong Kong 01", "Tokyo 02"])
    #expect(groups[0].nodes.first { $0.name == "Tokyo 02" }?.isSelected == true)
    #expect(groups[0].nodes.first { $0.name == "Hong Kong 01" }?.latency == 18)
    #expect(groups[0].nodes.first { $0.name == "Tokyo 02" }?.latency == 43)
}

@MainActor
@Test func appStoreKeepsMeasuredLatencyAcrossProxyListRefreshes() {
    let store = AppStore()
    store.proxyGroups = [testProxyGroup()]
    let data = """
    {
      "proxies": {
        "GLOBAL": {"type":"Selector","now":"Tokyo 02","all":["Hong Kong 01","Tokyo 02"]},
        "Hong Kong 01": {"type":"Shadowsocks"},
        "Tokyo 02": {"type":"Shadowsocks"}
      }
    }
    """.data(using: .utf8)!

    store.applyProxyResponse(data)

    let global = store.proxyGroups.first { $0.name == "GLOBAL" }
    #expect(global?.nodes.first { $0.name == "Hong Kong 01" }?.latency == 18)
    #expect(global?.nodes.first { $0.name == "Tokyo 02" }?.latency == 43)
}

@Test func mihomoAPIDecoderBuildsSemanticProxyGroups() throws {
    let data = """
    {
      "proxies": {
        "Mutdot": {
          "type":"Selector",
          "now":"自动选择",
          "all":["自动选择","香港HK04","日本JP04"]
        },
        "自动选择": {
          "type":"URLTest",
          "now":"香港HK04",
          "all":["香港HK04","日本JP04"],
          "testUrl":"http://www.gstatic.com/generate_204"
        },
        "香港HK04": {"type":"Trojan","history":[{"delay":18}]},
        "日本JP04": {"type":"Trojan","history":[{"delay":43}]}
      }
    }
    """.data(using: .utf8)!

    let groups = try MihomoAPIDecoder.proxyGroups(from: data)
    let selector = try #require(groups.first { $0.name == "Mutdot" })
    let automatic = try #require(groups.first { $0.name == "自动选择" })

    #expect(selector.kind == .selector)
    #expect(selector.nodes.first { $0.name == "自动选择" }?.isGroup == true)
    #expect(automatic.kind == .urlTest)
    #expect(automatic.testURL == "http://www.gstatic.com/generate_204")
    #expect(automatic.nodes.allSatisfy { !$0.isGroup })
    #expect(automatic.nodes.map(\.latency) == [18, 43])
}

@Test func proxySelectionResolverLocksAutomaticChildOnParentSelector() {
    let groups = [
        ProxyGroup(
            name: "GLOBAL",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "自动选择", region: "Automatic", latency: nil, isSelected: true, isGroup: true),
                ProxyNode(name: "香港HK04", region: "HK", latency: nil, isSelected: false),
                ProxyNode(name: "新加坡SG01", region: "SG", latency: nil, isSelected: false),
                ProxyNode(name: "日本JP04", region: "JP", latency: nil, isSelected: false),
                ProxyNode(name: "DIRECT", region: "Proxy", latency: nil, isSelected: false),
            ]
        ),
        ProxyGroup(
            name: "Mutdot",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "自动选择", region: "Automatic", latency: nil, isSelected: true, isGroup: true),
                ProxyNode(name: "香港HK04", region: "HK", latency: nil, isSelected: false),
                ProxyNode(name: "新加坡SG01", region: "SG", latency: nil, isSelected: false),
                ProxyNode(name: "日本JP04", region: "JP", latency: nil, isSelected: false),
            ]
        ),
        ProxyGroup(
            name: "自动选择",
            policy: "URLTest",
            kind: .urlTest,
            testURL: "http://www.gstatic.com/generate_204",
            nodes: [
                ProxyNode(name: "香港HK04", region: "HK", latency: nil, isSelected: true),
                ProxyNode(name: "日本JP04", region: "JP", latency: nil, isSelected: false),
            ]
        ),
    ]

    #expect(ProxySelectionResolver.targetGroup(
        selectedGroupName: "自动选择",
        nodeName: "日本JP04",
        groups: groups
    ) == "Mutdot")
    #expect(ProxySelectionResolver.targetGroup(
        selectedGroupName: "Mutdot",
        nodeName: "香港HK04",
        groups: groups
    ) == "Mutdot")
    #expect(ProxySelectionResolver.targetGroups(
        selectedGroupName: "GLOBAL",
        nodeName: "新加坡SG01",
        groups: groups
    ) == ["GLOBAL", "Mutdot"])
}

@Test func latencyRefreshPublishesUsefulProgressWhileTesting() {
    #expect(LatencyTestPlan.maximumConcurrentFallbackTests == 8)
    #expect(LatencyTestPlan.defaultTestURL == "http://www.gstatic.com/generate_204")
    #expect(LatencyTestProgress(completed: 0, total: 24).text == "Testing 0/24")
    #expect(LatencyTestProgress(completed: 7, total: 24).text == "Testing 7/24")
    #expect(LatencyTestProgress(completed: 24, total: 24).fraction == 1)
}

@Test func failedGroupMeasurementsFallBackToMissingNodes() {
    let test = LatencyGroupTest(
        groupName: "Automatic",
        url: "http://www.gstatic.com/generate_204",
        nodeNames: ["Hong Kong 01", "Tokyo 02"]
    )

    #expect(
        test.fallbackTests(excluding: ["Hong Kong 01"])
            == [LatencyProxyTest(
                proxyName: "Tokyo 02",
                url: "http://www.gstatic.com/generate_204"
            )]
    )
}

@Test func mihomoAPIDecoderIgnoresFailedLatencyHistorySentinels() throws {
    let data = """
    {
      "proxies": {
        "GLOBAL": {"type":"Selector","now":"Tokyo 02","all":["Tokyo 02"]},
        "Tokyo 02": {"type":"Trojan","history":[{"delay":43},{"delay":65535}]}
      }
    }
    """.data(using: .utf8)!

    let groups = try MihomoAPIDecoder.proxyGroups(from: data)

    #expect(groups[0].nodes[0].latency == 43)
}

@Test func latencySettingsNormalizeURLAndTimeout() {
    let settings = LatencyTestSettings(
        testURL: " https://cp.cloudflare.com/generate_204 ",
        timeoutMilliseconds: 2_500
    )

    #expect(settings.testURL == "https://cp.cloudflare.com/generate_204")
    #expect(settings.timeoutMilliseconds == 2_500)
    #expect(LatencyTestSettings(testURL: "", timeoutMilliseconds: 42).testURL == LatencyTestPlan.defaultTestURL)
    #expect(
        LatencyTestSettings(
            testURL: "ftp://example.com/check",
            timeoutMilliseconds: 90_000
        ).timeoutMilliseconds == LatencyTestSettings.maximumTimeoutMilliseconds
    )
}

@Test func latencyGroupDecoderBuildsNodeDelayMap() throws {
    let data = """
    {
      "香港HK01": 34,
      "日本JP01": 81
    }
    """.data(using: .utf8)!

    #expect(
        try MihomoAPIDecoder.groupDelays(from: data)
            == ["香港HK01": 34, "日本JP01": 81]
    )
}

@Test func latencyPlannerUsesAutomaticGroupsAndFallsBackOnlyForUncoveredNodes() {
    let groups = [
        ProxyGroup(
            name: "Manual",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "DIRECT", region: "Proxy", latency: nil, isSelected: false),
                ProxyNode(name: "REJECT", region: "Proxy", latency: nil, isSelected: false),
                ProxyNode(name: "香港HK01", region: "HK", latency: nil, isSelected: true),
                ProxyNode(name: "美国US01", region: "US", latency: nil, isSelected: false),
            ]
        ),
        ProxyGroup(
            name: "自动选择",
            policy: "URLTest",
            kind: .urlTest,
            testURL: "http://www.gstatic.com/generate_204",
            nodes: [
                ProxyNode(name: "香港HK01", region: "HK", latency: nil, isSelected: true),
                ProxyNode(name: "日本JP01", region: "JP", latency: nil, isSelected: false),
            ]
        ),
    ]

    let plan = LatencyTestPlanner.plan(
        groups: groups,
        settings: LatencyTestSettings(
            testURL: "https://cp.cloudflare.com/generate_204",
            timeoutMilliseconds: 3_000
        )
    )

    #expect(plan.groupTests.map(\.groupName) == ["自动选择"])
    #expect(plan.groupTests.first?.url == "http://www.gstatic.com/generate_204")
    #expect(plan.groupTests.first?.nodeNames == Set(["香港HK01", "日本JP01"]))
    #expect(plan.fallbackTests.map(\.proxyName) == ["美国US01"])
    #expect(plan.fallbackTests.first?.url == "https://cp.cloudflare.com/generate_204")
    #expect(!plan.nodeNames.contains("DIRECT"))
    #expect(!plan.nodeNames.contains("REJECT"))
}

@Test func latencyTestPrefersTheAutomaticGroupsConfiguredHTTPURL() {
    let groups = [
        ProxyGroup(
            name: "GLOBAL",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "新加坡SG01", region: "SG", latency: nil, isSelected: true),
            ]
        ),
        ProxyGroup(
            name: "自动选择",
            policy: "URLTest",
            kind: .urlTest,
            testURL: "http://www.gstatic.com/generate_204",
            nodes: [
                ProxyNode(name: "新加坡SG01", region: "SG", latency: nil, isSelected: true),
            ]
        ),
    ]

    #expect(
        LatencyTestTargetResolver.testURL(
            nodeName: "新加坡SG01",
            groups: groups
        ) == "http://www.gstatic.com/generate_204"
    )
    #expect(
        LatencyTestTargetResolver.testURL(
            nodeName: "不存在",
            groups: groups
        ) == LatencyTestPlan.defaultTestURL
    )
}

@MainActor
@Test func appStoreDelayRefreshUsesConfiguredLatencyDefaults() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("config.yaml")
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    mixed-port: 7890
    external-controller: 127.0.0.1:9090
    proxies: []
    rules:
      - MATCH,DIRECT
    """.write(to: sourceURL, atomically: true, encoding: .utf8)
    try """
    #!/bin/sh
    if [ "$1" = "-t" ]; then
      exit 0
    fi
    sleep 5
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    RecordingURLProtocol.useConfiguredLatencyDefaultsFixture()
    defer { RecordingURLProtocol.reset() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: executableURL),
        apiService: MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!),
            session: session
        ),
        profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
        runtimeConfigurationPreparer: RuntimeConfigurationPreparer(
            portAllocator: RuntimePortAllocator(
                isTCPPortAvailable: { _, _ in true },
                isUDPPortAvailable: { _, _ in true }
            )
        )
    )
    store.configPath = sourceURL.path
    store.latencyTestURL = "https://cp.cloudflare.com/generate_204"
    store.latencyTestTimeoutMilliseconds = 2_500

    await store.refreshProxiesAndLatency()
    await store.shutdownRuntime()

    let measuredLatency = store.proxyGroups
        .first { $0.name == "Automatic" }?
        .nodes.first?
        .latency
    let requestTrace = RecordingURLProtocol.observedRequests.joined(separator: " | ")
    #expect(
        measuredLatency == 123,
        "Expected configured latency request to return 123 ms. Requests: \(requestTrace)"
    )
}

@Test func proxyGroupsCollapseIndependently() {
    var state = ProxyGroupExpansionState()

    #expect(state.isExpanded("GLOBAL"))
    #expect(state.isExpanded("Streaming"))

    state.toggle("GLOBAL")

    #expect(!state.isExpanded("GLOBAL"))
    #expect(state.isExpanded("Streaming"))

    state.toggle("GLOBAL")

    #expect(state.isExpanded("GLOBAL"))
}

@MainActor
@Test func menuBarQuickNodesUseOnlyConcreteMutdotEntries() {
    let store = AppStore()
    store.proxyGroups = [
        ProxyGroup(
            name: "GLOBAL",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "香港HK01", region: "HK", latency: 18, isSelected: true),
            ]
        ),
        ProxyGroup(
            name: "Mutdot",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(
                    name: "自动选择",
                    region: "Proxy",
                    latency: nil,
                    isSelected: false,
                    isGroup: true
                ),
                ProxyNode(name: "香港HK01", region: "HK", latency: 18, isSelected: false),
                ProxyNode(name: "新加坡SG01", region: "SG", latency: 56, isSelected: true),
            ]
        ),
    ]

    #expect(MenuBarQuickAccessPolicy.selectorName == "Mutdot")
    #expect(store.menuBarProxyNodes.map(\.name) == ["香港HK01", "新加坡SG01"])
    #expect(store.menuBarSelectedNodeName == "新加坡SG01")
}

@MainActor
@Test func menuBarHeaderResolvesAutomaticGroupToConnectedServer() {
    let store = AppStore()
    store.proxyGroups = [
        ProxyGroup(
            name: "Mutdot",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(
                    name: "自动选择",
                    region: "Proxy",
                    latency: nil,
                    isSelected: true,
                    isGroup: true
                ),
                ProxyNode(name: "香港HK01", region: "HK", latency: 18, isSelected: false),
                ProxyNode(name: "新加坡SG01", region: "SG", latency: 56, isSelected: false),
            ]
        ),
        ProxyGroup(
            name: "自动选择",
            policy: "URLTest",
            kind: .urlTest,
            nodes: [
                ProxyNode(name: "香港HK01", region: "HK", latency: 18, isSelected: false),
                ProxyNode(name: "新加坡SG01", region: "SG", latency: 56, isSelected: true),
            ]
        ),
    ]

    #expect(store.menuBarSelectedNodeName == "新加坡SG01")
    #expect(store.menuBarHeaderTitle == "新加坡SG01")
    #expect(store.menuBarProxyNodes.first(where: { $0.name == "新加坡SG01" })?.isSelected == true)
}

@Test func selectedLeafResolverStopsAtCyclicProxyGroups() {
    let groups = [
        ProxyGroup(
            name: "A",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "B", region: "Proxy", latency: nil, isSelected: true, isGroup: true),
            ]
        ),
        ProxyGroup(
            name: "B",
            policy: "Selector",
            kind: .selector,
            nodes: [
                ProxyNode(name: "A", region: "Proxy", latency: nil, isSelected: true, isGroup: true),
            ]
        ),
    ]

    #expect(
        ProxySelectionResolver.selectedLeafNodeName(
            selectedGroupName: "A",
            groups: groups
        ) == nil
    )
}

@Test func menuBarPanelUsesOneMainSwitchAndFitsItsWindow() {
    #expect(MenuBarQuickAccessPolicy.visibleConnectionControlCount == 1)
    #expect(!MenuBarQuickAccessPolicy.showsSystemProxyToggle)
    #expect(!MenuBarQuickAccessPolicy.showsTunToggle)
    #expect(!MenuBarQuickAccessPolicy.showsOpenMainWindowButton)
    #expect(MenuBarQuickAccessPolicy.clipsNodeViewport)
    #expect(MenuBarQuickAccessPolicy.topInset == MenuBarQuickAccessPolicy.bottomInset)
    #expect(MenuBarQuickAccessPolicy.requiredContentHeight == MenuBarQuickAccessPolicy.panelHeight)
}

@Test func menuBarPanelUsesASlowerWindowLevelFadeWithoutContentFlashing() {
    #expect(MenuBarPanelMotion.usesCustomWindowAnimator)
    #expect(!MenuBarPanelMotion.usesCustomContentFade)
    #expect(MenuBarPanelMotion.startsWindowTransparent)
    #expect(MenuBarPanelMotion.respectsReducedMotion)
    #expect(MenuBarPanelMotion.fadeInDuration >= 0.28)
    #expect(MenuBarPanelMotion.fadeOutDuration >= 0.20)
}

@Test func mihomoAPIDecoderBuildsConnectionRowsFromMihomoResponse() throws {
    let data = """
    {
      "connections": [
        {
          "id":"a",
          "metadata":{"host":"api.github.com","destinationPort":"443"},
          "upload":42000,
          "download":1200000,
          "chains":["GLOBAL","Hong Kong 01"],
          "rule":"DOMAIN-SUFFIX",
          "rulePayload":"github.com"
        }
      ]
    }
    """.data(using: .utf8)!

    let rows = try MihomoAPIDecoder.connections(from: data)

    #expect(rows.first?.host == "api.github.com:443")
    #expect(rows.first?.rule == "DOMAIN-SUFFIX,github.com")
    #expect(rows.first?.chain == "GLOBAL / Hong Kong 01")
    #expect(rows.first?.upload == "42.0 KB")
    #expect(rows.first?.download == "1.2 MB")
}

@Test func mihomoAPIDecoderBuildsConnectionTotals() throws {
    let data = """
    {
      "downloadTotal": 2500000,
      "uploadTotal": 1250000,
      "connections": []
    }
    """.data(using: .utf8)!

    let snapshot = try MihomoAPIDecoder.connectionsSnapshot(from: data)

    #expect(snapshot.uploadTotal == 1_250_000)
    #expect(snapshot.downloadTotal == 2_500_000)
    #expect(snapshot.entries.isEmpty)
}

@Test func networkIdentityDecoderBuildsCountryFlag() throws {
    let data = """
    {
      "success": true,
      "ip": "151.243.38.149",
      "country_code": "HK",
      "country": "Hong Kong"
    }
    """.data(using: .utf8)!

    let identity = try NetworkIdentityDecoder.decode(data)

    #expect(identity.ip == "151.243.38.149")
    #expect(identity.countryCode == "HK")
    #expect(identity.countryName == "Hong Kong")
    #expect(identity.flagEmoji == "🇭🇰")
}

@Test func networkIdentityAcceptsOnlyIPv4ForDashboardDisplay() {
    #expect(NetworkAddressPolicy.isIPv4("151.243.38.149"))
    #expect(!NetworkAddressPolicy.isIPv4("2409:8a1e:14f2:a890:48fb:e3f0:1"))
    #expect(!NetworkAddressPolicy.isIPv4("999.1.1.1"))
}

@MainActor
@Test func appStoreAppliesTrafficSnapshotToDashboardState() {
    let store = AppStore()
    let data = #"{"up":5900,"down":33300}"#.data(using: .utf8)!

    store.applyTrafficResponse(data)

    #expect(store.uploadSpeedText == "5.9KB/s")
    #expect(store.downloadSpeedText == "33.3KB/s")
    #expect(store.speedSamples.last ?? 0 > 0)
}

@MainActor
@Test func appStoreUsesZeroedRollingTrafficWindow() {
    let store = AppStore()

    #expect(store.speedSamples.count == 28)
    #expect(store.speedSamples.allSatisfy { $0 == 0 })

    for index in 1...30 {
        let data = #"{"up":\#(index * 1000),"down":\#(index * 2000)}"#
            .data(using: .utf8)!
        store.applyTrafficResponse(data)
    }

    #expect(store.speedSamples.count == 28)
    #expect(store.speedSamples.last == 0.06)
}

@MainActor
@Test func appStoreAdvancesHalfSecondGraphFromLatestTrafficStreamValue() {
    let store = AppStore()
    let traffic = #"{"up":1000,"down":2000}"#.data(using: .utf8)!

    store.applyLiveTrafficResponse(traffic)
    store.advanceSpeedGraph()

    #expect(store.uploadSpeedText == "1.0KB/s")
    #expect(store.downloadSpeedText == "2.0KB/s")
    #expect(store.speedSamples.last == 0.002)
}

@MainActor
@Test func appStoreSelectsProxyInsideGroup() {
    let store = AppStore()
    store.proxyGroups = [testProxyGroup()]

    store.selectProxy(groupName: "GLOBAL", nodeName: "Tokyo 02")

    let global = store.proxyGroups.first { $0.name == "GLOBAL" }
    #expect(global?.nodes.first { $0.name == "Tokyo 02" }?.isSelected == true)
    #expect(global?.nodes.first { $0.name == "Hong Kong 01" }?.isSelected == false)
}

@MainActor
@Test func outboundModeSelectionStagesBeforeRuntimeStarts() async {
    let store = AppStore()

    await store.setOutboundMode(.global)

    #expect(store.selectedMode == .global)
    #expect(store.stagedOutboundMode == .global)
}

@MainActor
@Test func appStoreRestoresProxySelectionWhenRemoteChangeFails() async {
    let store = AppStore(
        apiService: MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:1")!)
        )
    )
    store.proxyGroups = [testProxyGroup()]

    await store.selectProxyRemote(groupName: "GLOBAL", nodeName: "Tokyo 02")

    let global = store.proxyGroups.first { $0.name == "GLOBAL" }
    #expect(global?.nodes.first { $0.name == "Hong Kong 01" }?.isSelected == true)
    #expect(global?.nodes.first { $0.name == "Tokyo 02" }?.isSelected == false)
    #expect(store.lastErrorMessage != nil)
}

private func testProxyGroup() -> ProxyGroup {
    ProxyGroup(
        name: "GLOBAL",
        policy: "Manual",
        kind: .selector,
        nodes: [
            ProxyNode(name: "Hong Kong 01", region: "HK", latency: 18, isSelected: true),
            ProxyNode(name: "Tokyo 02", region: "JP", latency: 43, isSelected: false),
        ]
    )
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private enum Fixture: Sendable {
        case empty
        case configuredLatencyDefaults
    }

    private struct StubResponse: Sendable {
        let statusCode: Int
        let data: Data
    }

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var fixtureStorage = Fixture.empty
    nonisolated(unsafe) private static var observedRequestStorage: [String] = []

    static var observedRequests: [String] {
        withStateLock { observedRequestStorage }
    }

    static func useConfiguredLatencyDefaultsFixture() {
        withStateLock {
            fixtureStorage = .configuredLatencyDefaults
            observedRequestStorage = []
        }
    }

    static func reset() {
        withStateLock {
            fixtureStorage = .empty
            observedRequestStorage = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.record(request)
        let stub = Self.stubResponse(for: request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func record(_ request: URLRequest) {
        withStateLock {
            observedRequestStorage.append(request.url?.absoluteString ?? "<missing URL>")
        }
    }

    private static func stubResponse(for request: URLRequest) -> StubResponse {
        let fixture = withStateLock { fixtureStorage }
        switch fixture {
        case .empty:
            return StubResponse(statusCode: 200, data: Data())
        case .configuredLatencyDefaults:
            return configuredLatencyDefaultsResponse(for: request)
        }
    }

    private static func configuredLatencyDefaultsResponse(for request: URLRequest) -> StubResponse {
        guard let url = request.url else {
            return StubResponse(statusCode: 400, data: Data())
        }
        let pathComponents = url.pathComponents
            .map { $0.removingPercentEncoding ?? $0 }
            .filter { $0 != "/" }

        switch pathComponents.last {
        case "version":
            return StubResponse(
                statusCode: 200,
                data: Data(#"{"version":"test"}"#.utf8)
            )
        case "proxies":
            return StubResponse(
                statusCode: 200,
                data: Data("""
                {
                  "proxies": {
                    "GLOBAL": {"type":"Selector","now":"Automatic","all":["Automatic"]},
                    "Automatic": {
                      "type":"URLTest",
                      "now":"Hong Kong 01",
                      "all":["Hong Kong 01"],
                      "testUrl":"https://cp.cloudflare.com/generate_204"
                    },
                    "Hong Kong 01": {"type":"Shadowsocks"}
                  }
                }
                """.utf8)
            )
        default:
            let queryItems = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []
            let query = Dictionary(
                uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") }
            )
            guard query["url"] != nil || query["timeout"] != nil else {
                return StubResponse(statusCode: 404, data: Data())
            }
            if pathComponents.contains("group") {
                return StubResponse(
                    statusCode: 504,
                    data: Data(#"{"message":"get delay: all proxies timeout"}"#.utf8)
                )
            }
            let receivedConfiguredDefaults = query["url"] == "https://cp.cloudflare.com/generate_204"
                && query["timeout"] == "2500"
            return StubResponse(
                statusCode: receivedConfiguredDefaults ? 200 : 400,
                data: Data("{\"delay\":\(receivedConfiguredDefaults ? 123 : 1)}".utf8)
            )
        }
    }

    private static func withStateLock<T>(_ operation: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation()
    }
}

@Test func proxyRegionDecoderRecognizesChineseNodeNames() {
    #expect(MihomoAPIDecoder.regionCode(from: "香港节点") == "HK")
    #expect(MihomoAPIDecoder.regionCode(from: "日本节点") == "JP")
    #expect(MihomoAPIDecoder.regionCode(from: "美国节点") == "US")
    #expect(MihomoAPIDecoder.regionCode(from: "新加坡节点") == "SG")
}

@MainActor
@Test func coreServiceDoesNotStartWhenCoreBinaryIsMissing() async {
    let service = MihomoCoreService(coreBinaryURL: nil)

    await service.start(configPath: "/path/is/not/used/without/a/core.yaml")

    #expect(!service.isProcessRunning)
    #expect(service.status == .missingCoreBinary)
}

@Test func coreResolverPrefersExecutableBundledCandidates() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let nonExecutable = directory.appendingPathComponent("clash")
    let executable = directory.appendingPathComponent("mihomo")

    FileManager.default.createFile(atPath: nonExecutable.path, contents: Data())
    FileManager.default.createFile(atPath: executable.path, contents: Data())
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    let resolved = MihomoCoreService.candidateCoreBinaryURL(paths: [nonExecutable.path, executable.path])

    #expect(resolved == executable)
}

@MainActor
@Test func coreServiceCreatesDefaultLaunchConfigWhenMissing() throws {
    let service = MihomoCoreService(coreBinaryURL: nil)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configURL = directory.appendingPathComponent("config.yaml")

    try service.ensureLaunchConfig(path: configURL.path)

    let content = try String(contentsOf: configURL, encoding: .utf8)
    #expect(content.contains("mixed-port: 7890"))
    #expect(content.contains("external-controller: 127.0.0.1:9090"))
    #expect(content.contains("MATCH,DIRECT"))
}

@MainActor
@Test func appStoreBuildsSystemProxyCommandFromCurrentPorts() {
    let store = AppStore()
    store.httpPort = 7890
    store.socksPort = 7891
    store.setSystemProxyEnabled(false)

    let disable = store.currentSystemProxyCommand(service: "Wi-Fi")
    #expect(disable.steps.first?.arguments == ["-setwebproxystate", "Wi-Fi", "off"])

    store.setSystemProxyEnabled(true)
    let enable = store.currentSystemProxyCommand(service: "Wi-Fi")
    #expect(enable.steps.map(\.arguments) == [
        ["-setwebproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "7891"],
    ])
}
