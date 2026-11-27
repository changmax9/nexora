import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

private let providerSelectorResponse = Data(#"""
{
  "proxies": {
    "GLOBAL": {"type":"Selector","now":"Routes","all":["Routes","DIRECT"]},
    "Routes": {"type":"Selector","now":"Tokyo 02","all":["Hong Kong 01","Tokyo 02"]},
    "DIRECT": {"type":"Direct","history":[]}
  }
}
"""#.utf8)

private let providerMetadataResponse = Data(#"""
{
  "providers": {
    "Subscription / Primary": {
      "type":"Proxy",
      "proxies":[
        {"name":"Hong Kong 01","type":"Shadowsocks","history":[{"delay":85},{"delay":18}]},
        {"name":"Tokyo 02","type":"Shadowsocks","history":[{"delay":43}]}
      ]
    }
  }
}
"""#.utf8)

@Test func providerMetadataRestoresLeafHistoryWithoutChangingSelectorState() throws {
    let groups = try MihomoAPIDecoder.proxyGroups(
        from: providerSelectorResponse, providerData: providerMetadataResponse
    )
    let global = try #require(groups.first { $0.name == "GLOBAL" })
    let routes = try #require(groups.first { $0.name == "Routes" })

    #expect(global.nodes.first { $0.isSelected }?.name == "Routes")
    #expect(global.nodes.first { $0.name == "Routes" }?.isGroup == true)
    #expect(routes.kind == .selector)
    #expect(routes.nodes.first { $0.isSelected }?.name == "Tokyo 02")
    #expect(routes.nodes.map(\.latency) == [18, 43])
    #expect(routes.nodes.allSatisfy { $0.providerName == "Subscription / Primary" })
    #expect(ProxySelectionResolver.selectedLeafNodeName(
        selectedGroupName: "GLOBAL", groups: groups
    ) == "Tokyo 02")
}

@Test func oldControllersKeepTopLevelNodeMetadataAndAcceptMissingProviders() throws {
    let oldResponse = Data(#"""
    {"proxies":{
      "Routes":{"type":"Selector","now":"Tokyo 02","all":["Hong Kong 01","Tokyo 02"]},
      "Hong Kong 01":{"type":"Shadowsocks","history":[{"delay":27}]},
      "Tokyo 02":{"type":"Shadowsocks","history":[{"delay":52}]}
    }}
    """#.utf8)
    for providerData in [nil, Data(#"{"message":"not found"}"#.utf8), providerMetadataResponse] {
        let routes = try #require(MihomoAPIDecoder.proxyGroups(
            from: oldResponse, providerData: providerData
        ).first)
        #expect(routes.nodes.map(\.latency) == [27, 52])
        #expect(routes.nodes.first { $0.isSelected }?.name == "Tokyo 02")
        #expect(routes.nodes.allSatisfy { $0.providerName == nil })
    }
}

@Test func manualSelectorProviderNodesUseProviderLatencyEndpoints() throws {
    let groups = try MihomoAPIDecoder.proxyGroups(
        from: providerSelectorResponse, providerData: providerMetadataResponse
    )
    let plan = LatencyTestPlanner.plan(groups: groups)

    #expect(plan.groupTests.isEmpty)
    #expect(plan.fallbackTests.map(\.proxyName) == ["Hong Kong 01", "Tokyo 02"])
    #expect(plan.fallbackTests.allSatisfy { $0.providerName == "Subscription / Primary" })
    #expect(!plan.nodeNames.contains("Routes"))
    #expect(!plan.nodeNames.contains("DIRECT"))
}

@Test func automaticGroupFallbackRetainsProviderMembership() throws {
    let response = Data(#"""
    {"proxies":{
      "Automatic":{"type":"URLTest","now":"Tokyo 02","all":["Hong Kong 01","Tokyo 02"]}
    }}
    """#.utf8)
    let groups = try MihomoAPIDecoder.proxyGroups(
        from: response, providerData: providerMetadataResponse
    )
    let groupTest = try #require(LatencyTestPlanner.plan(groups: groups).groupTests.first)
    let fallback = try #require(groupTest.fallbackTests(excluding: ["Hong Kong 01"]).first)

    #expect(fallback.proxyName == "Tokyo 02")
    #expect(fallback.providerName == "Subscription / Primary")
}

@Test func providerHealthcheckEncodesProviderAndNodeAsSeparatePathSegments() throws {
    let builder = MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!, secret: "fixture")
    let providers = try builder.urlRequest(for: .proxyProviders)
    let request = try builder.urlRequest(for: .providerDelayTest(
        provider: "Subscription / Primary", proxy: "HK / 01?fast#1",
        url: "https://example.test/generate_204", timeout: 2_500
    ))

    #expect(providers.url?.absoluteString == "http://127.0.0.1:9090/providers/proxies")
    #expect(request.url?.absoluteString == "http://127.0.0.1:9090/providers/proxies/Subscription%20%2F%20Primary/HK%20%2F%2001%3Ffast%231/healthcheck?url=https://example.test/generate_204&timeout=2500")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
}

@Test func providerLatencyUsesHealthcheckWhenLeafIsAbsentFromLegacyProxies() async throws {
    let fixture = ProviderCompatibilityFixture { request in
        request.url?.path.hasSuffix("/healthcheck") == true
            ? (200, Data(#"{"delay":173}"#.utf8))
            : (404, Data(#"{"message":"Proxy not found"}"#.utf8))
    }
    defer { fixture.finish() }

    let delay = await fixture.service.proxyDelay(
        proxy: "Tokyo 02", url: LatencyTestPlan.defaultTestURL,
        provider: "Subscription / Primary"
    )

    #expect(delay == 173)
    #expect(fixture.requests.count == 1)
    #expect(fixture.requests.first?.url?.path.hasSuffix("/healthcheck") == true)
    #expect(fixture.requests.allSatisfy { $0.httpMethod == "GET" })
}

@Test func providerLatencyFallsBackToLegacyEndpointOnlyWhenUnsupported() async throws {
    for status in [404, 405, 503] {
        let fixture = ProviderCompatibilityFixture { request in
            request.url?.path.hasSuffix("/healthcheck") == true
                ? (status, Data(#"{"message":"provider healthcheck unavailable"}"#.utf8))
                : (200, Data(#"{"delay":61}"#.utf8))
        }
        defer { fixture.finish() }
        let delay = await fixture.service.proxyDelay(
            proxy: "Tokyo 02", url: LatencyTestPlan.defaultTestURL,
            provider: "Subscription / Primary"
        )

        #expect(delay == (status == 503 ? nil : 61))
        #expect(fixture.requests.count == (status == 503 ? 1 : 2))
        if status != 503 {
            #expect(fixture.requests.last?.url?.path == "/proxies/Tokyo 02/delay")
        }
    }
}

@MainActor
@Test func appStoreAppliesProviderMetadataAndKeepsMeasuredLatencyAcrossRefresh() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suiteName = "ProviderCompatibilityTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: nil),
        profileRepository: ManagedProfileRepository(rootURL: root),
        userDefaults: defaults
    )
    store.applyProxyResponse(
        providerSelectorResponse, providerData: providerMetadataResponse, profileID: nil
    )
    let routeIndex = try #require(store.proxyGroups.firstIndex { $0.name == "Routes" })
    #expect(store.proxyGroups[routeIndex].nodes.first?.latency == 18)
    store.proxyGroups[routeIndex].nodes[0].latency = 99
    store.applyProxyResponse(
        providerSelectorResponse, providerData: providerMetadataResponse, profileID: nil
    )

    let routes = try #require(store.proxyGroups.first { $0.name == "Routes" })
    #expect(routes.nodes.first?.latency == 99)
    #expect(routes.nodes.first { $0.isSelected }?.name == "Tokyo 02")
    #expect(routes.nodes.first?.providerName == "Subscription / Primary")
    #expect(store.lastErrorMessage == nil)
}

private final class ProviderCompatibilityFixture: @unchecked Sendable {
    let identifier = UUID().uuidString
    let handler: @Sendable (URLRequest) -> (Int, Data)
    let observedRequests = Mutex<[URLRequest]>([])
    private var session: URLSession!

    var requests: [URLRequest] { observedRequests.withLock { $0 } }
    var service: MihomoAPIService {
        MihomoAPIService(
            requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!),
            session: session
        )
    }

    init(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
        ProviderCompatibilityURLProtocol.fixtures.withLock { $0[identifier] = self }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderCompatibilityURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Provider-Fixture": identifier]
        session = URLSession(configuration: configuration)
    }

    func finish() {
        session.invalidateAndCancel()
        _ = ProviderCompatibilityURLProtocol.fixtures.withLock { $0.removeValue(forKey: identifier) }
    }
}

private final class ProviderCompatibilityURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = Mutex<[String: ProviderCompatibilityFixture]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let identifier = request.value(forHTTPHeaderField: "X-Provider-Fixture"),
              let fixture = Self.fixtures.withLock({ $0[identifier] }),
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        fixture.observedRequests.withLock { $0.append(request) }
        let (status, data) = fixture.handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
