import Foundation
import Testing
@testable import ClashGlassCore

@MainActor
@Test func liveRoutingOverridesValidateWithMihomo() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let configPath = environment["CLASH_GLASS_LIVE_CONFIG"],
          let corePath = environment["CLASH_GLASS_LIVE_CORE"],
          let geoDataPath = environment["CLASH_GLASS_LIVE_GEODATA"] else {
        return
    }

    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClashGlassRouting-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let prepared = try RuntimeConfigurationPreparer(
        geoDataSourceURL: URL(fileURLWithPath: geoDataPath, isDirectory: true)
    ).prepare(
        sourceURL: URL(fileURLWithPath: configPath),
        runtimeDirectoryURL: rootURL,
        routingOverrides: [
            RoutingOverride(domain: "openai.com", policy: .vpn),
            RoutingOverride(domain: "example.cn", policy: .direct),
        ]
    )
    let validation = await MihomoCoreService(
        coreBinaryURL: URL(fileURLWithPath: corePath)
    ).validateConfig(path: prepared.configURL.path)
    let yaml = try String(contentsOf: prepared.configURL, encoding: .utf8)
    if validation != .success {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: corePath)
        process.arguments = ["-t", "-d", rootURL.path, "-f", prepared.configURL.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let detail = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        print("LIVE_ROUTING_VALIDATION_ERROR\n\(detail)")
    }

    #expect(validation == .success)
    #expect(yaml.contains("'DOMAIN-SUFFIX,openai.com,SampleRoutes'"))
    #expect(yaml.contains("'DOMAIN-SUFFIX,example.cn,DIRECT'"))
}

@MainActor
@Test func liveRuntimeConnectsSwitchesAndRestoresSystemProxy() async {
    let environment = ProcessInfo.processInfo.environment
    guard let configPath = environment["CLASH_GLASS_LIVE_CONFIG"],
          let corePath = environment["CLASH_GLASS_LIVE_CORE"],
          let geoDataPath = environment["CLASH_GLASS_LIVE_GEODATA"] else {
        return
    }

    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClashGlassLive-\(UUID().uuidString)", isDirectory: true)
    let repository = ManagedProfileRepository(rootURL: rootURL)
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: URL(fileURLWithPath: corePath)),
        profileRepository: repository,
        runtimeConfigurationPreparer: RuntimeConfigurationPreparer(
            geoDataSourceURL: URL(fileURLWithPath: geoDataPath, isDirectory: true)
        )
    )
    let proxyService = SystemProxyService()
    let proxyBefore = try? proxyService.capture(service: store.networkService)
    var persistedTarget: String?

    await store.importManagedProfile(from: URL(fileURLWithPath: configPath))
    #expect(store.lastErrorMessage == nil)

    await store.refreshProxiesAndLatency()
    #expect(store.isCoreRunning)
    #expect(store.isStarted == false)
    #expect(store.isLatencyTesting == false)
    #expect(store.latencyTestProgress.completed == store.latencyTestProgress.total)
    #expect(store.latencyTestProgress.total > 0)
    #expect(
        store.proxyGroups
            .flatMap(\.nodes)
            .contains(where: { !$0.isGroup && $0.latency != nil })
    )
    let proxyAfterRefresh = try? proxyService.capture(service: store.networkService)
    #expect(proxyAfterRefresh == proxyBefore)
    let directIdentity = try? await NetworkIdentityService().fetchDirect()
    print(
        "LIVE_DIRECT_IP ip=\(directIdentity?.ip ?? "unavailable") "
            + "country=\(directIdentity?.countryCode ?? "--")"
    )
    #expect(directIdentity?.ip.isEmpty == false)
    #expect(directIdentity?.countryCode.count == 2)

    if let global = store.proxyGroups.first(where: { $0.name == "GLOBAL" }),
       let taiwan = global.nodes.first(where: { $0.region == "TW" && !$0.isGroup }),
       let singapore = global.nodes.first(where: { $0.region == "SG" && !$0.isGroup }) {
        await store.selectProxyRemote(groupName: global.name, nodeName: taiwan.name)
        let taiwanIdentity = try? await NetworkIdentityService()
            .fetchViaProxy(host: store.proxyHost, port: store.httpPort)
        #expect(taiwanIdentity?.countryCode == "TW")

        await store.selectProxyRemote(groupName: global.name, nodeName: singapore.name)
        let proxiesURL = store.controllerURL.appendingPathComponent("proxies")
        let proxyData = try? await URLSession.shared.data(from: proxiesURL).0
        let object = proxyData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let proxies = object?["proxies"] as? [String: Any]
        let globalRemote = proxies?["GLOBAL"] as? [String: Any]
        let selectorRemote = proxies?["SampleRoutes"] as? [String: Any]
        print(
            "LIVE_GLOBAL_SELECTION target=\(singapore.name) "
                + "global=\(globalRemote?["now"] as? String ?? "--") "
                + "selector=\(selectorRemote?["now"] as? String ?? "--")"
        )
        #expect(globalRemote?["now"] as? String == singapore.name)
        #expect(selectorRemote?["now"] as? String == singapore.name)
        let singaporeIdentity = try? await NetworkIdentityService()
            .fetchViaProxy(host: store.proxyHost, port: store.httpPort)
        print(
            "LIVE_GLOBAL_EXIT target=\(singapore.name) "
                + "ip=\(singaporeIdentity?.ip ?? "--") "
                + "country=\(singaporeIdentity?.countryCode ?? "--")"
        )
        #expect(singaporeIdentity?.countryCode == "SG")
    } else {
        Issue.record("The live GLOBAL group did not expose Taiwan and Singapore nodes.")
    }

    if let automatic = store.proxyGroups.first(where: { $0.kind == .urlTest }),
       let target = automatic.nodes.first(where: { !$0.isSelected && !$0.isGroup }) {
        persistedTarget = target.name
        let resolvedGroup = ProxySelectionResolver.targetGroup(
            selectedGroupName: automatic.name,
            nodeName: target.name,
            groups: store.proxyGroups
        )
        await store.selectProxyRemote(groupName: automatic.name, nodeName: target.name)
        let proxiesURL = store.controllerURL.appendingPathComponent("proxies")
        let proxyData = try? await URLSession.shared.data(from: proxiesURL).0
        let object = proxyData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let proxies = object?["proxies"] as? [String: Any]
        let parent = proxies?["SampleRoutes"] as? [String: Any]
        print(
            "LIVE_SELECTION group=\(automatic.name) resolved=\(resolvedGroup ?? "--") target=\(target.name) "
                + "localParent=\(store.proxyGroups.first(where: { $0.name == "SampleRoutes" })?.nodes.first(where: { $0.isSelected })?.name ?? "--") "
                + "remoteParent=\(parent?["now"] as? String ?? "--") "
                + "error=\(store.lastErrorMessage ?? "none")"
        )
        #expect(parent?["now"] as? String == target.name)

        let liveAPI = MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: store.controllerURL)
        )
        do {
            let singleData = try await liveAPI.data(
                for: .delayTest(
                    proxy: target.name,
                    url: automatic.testURL ?? "http://www.gstatic.com/generate_204",
                    timeout: 5_000
                )
            )
            print("LIVE_SINGLE_RTT \(String(data: singleData, encoding: .utf8) ?? "--")")
        } catch {
            print("LIVE_SINGLE_RTT_ERROR \(error)")
        }
        let measuredLatency = store.proxyGroups
            .first(where: { $0.name == automatic.name })?
            .nodes.first(where: { $0.name == target.name })?
            .latency
        print("LIVE_HTTP_RTT node=\(target.name) delay=\(measuredLatency.map(String.init) ?? "--")ms")
        #expect(measuredLatency != nil)
    } else {
        Issue.record("The live automatic group did not expose a concrete alternate node.")
    }

    await store.setOutboundMode(.global)
    #expect(store.selectedMode == .global)
    #expect(store.stagedOutboundMode == nil)

    await store.toggleRuntime(configPath: store.configPath)
    #expect(store.isStarted)
    #expect(store.coreStatus == .running)
    #expect(store.lastErrorMessage == nil)
    #expect(store.selectedMode == .global)
    #expect(store.stagedOutboundMode == nil)

    if store.isStarted {
        let versionData = try? await URLSession.shared.data(from: store.controllerURL.appendingPathComponent("version")).0
        let versionText = versionData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(versionText.contains("version"))

        await store.refreshProxies()
        if let group = store.proxyGroups.first(where: { $0.name == "SampleRoutes" }),
           let target = group.nodes.first(where: { !$0.isSelected && $0.region == "HK" }) {
            persistedTarget = target.name
            await store.selectProxyRemote(groupName: group.name, nodeName: target.name)
            let selected = store.proxyGroups
                .first(where: { $0.name == group.name })?
                .nodes.first(where: { $0.name == target.name })?
                .isSelected
            #expect(selected == true)
        } else {
            Issue.record("The live SampleRoutes proxy group did not expose an unselected Hong Kong node.")
        }

        let identity = try? await NetworkIdentityService()
            .fetchViaProxy(host: store.proxyHost, port: store.httpPort)
        #expect(identity?.ip.isEmpty == false)
        #expect(identity?.countryCode.count == 2)

        try? await Task.sleep(for: .milliseconds(1_100))
        await store.runtimeTick()
        #expect(store.speedSamples.last ?? 0 > 0)

        await store.setOutboundMode(.direct)
        #expect(store.selectedMode == .direct)

        await store.setOutboundMode(.rule)
        #expect(store.selectedMode == .rule)

        print(
            "LIVE_RUNTIME controller=\(store.controllerURL.absoluteString) "
                + "mixedPort=\(store.httpPort) "
                + "exitIP=\(identity?.ip ?? "unavailable") "
                + "country=\(identity?.countryCode ?? "--") "
                + "up=\(store.uploadSpeedText) "
                + "down=\(store.downloadSpeedText)"
        )

        store.shutdownForApplicationTermination()
    }

    #expect(store.isStarted == false)
    #expect(store.coreStatus == .stopped)
    await store.refreshProxies()
    let restoredSelection = store.proxyGroups
        .first(where: { $0.name == "SampleRoutes" })?
        .nodes.first(where: { $0.isSelected })?
        .name
    #expect(restoredSelection == persistedTarget)
    let proxyAfterRestoreRefresh = try? proxyService.capture(service: store.networkService)
    #expect(proxyAfterRestoreRefresh == proxyBefore)
    await store.shutdownRuntime()
    try? FileManager.default.removeItem(at: rootURL)
}
