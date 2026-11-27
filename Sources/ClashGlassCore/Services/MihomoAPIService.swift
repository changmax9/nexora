import CFNetwork
import Foundation

public enum MihomoAPIEndpoint: Equatable, Sendable {
    case version
    case configs
    case proxies
    case proxyProviders
    case connections
    case traffic
    case updateConfigs(mode: OutboundMode?, tunEnabled: Bool?)
    case changeProxy(group: String, proxy: String)
    case groupDelay(group: String, url: String, timeout: Int)
    case delayTest(proxy: String, url: String, timeout: Int)
    case providerDelayTest(provider: String, proxy: String, url: String, timeout: Int)
    case closeConnection(id: String)
    case closeAllConnections
}

public struct MihomoAPIRequest: Sendable {
    public let baseURL: URL
    public let secret: String?

    public init(baseURL: URL, secret: String? = nil) {
        self.baseURL = baseURL
        self.secret = secret
    }

    public func urlRequest(for endpoint: MihomoAPIEndpoint) throws -> URLRequest {
        var request = URLRequest(url: url(for: endpoint))
        request.httpMethod = method(for: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout(for: endpoint)
        if let secret, !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        if let body = body(for: endpoint) {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func timeout(for endpoint: MihomoAPIEndpoint) -> TimeInterval {
        switch endpoint {
        case .version:
            return 2
        case let .groupDelay(_, _, milliseconds),
             let .delayTest(_, _, milliseconds),
             let .providerDelayTest(_, _, _, milliseconds):
            // Give Mihomo enough time to return the configured probe result.
            return max(5, Double(milliseconds) / 1_000 + 2)
        case .traffic:
            // This is an ongoing stream, rather than a controller transaction.
            return 60
        default:
            return 5
        }
    }

    private func url(for endpoint: MihomoAPIEndpoint) -> URL {
        switch endpoint {
        case .version:
            return baseURL.appendingPathComponent("version")
        case .configs, .updateConfigs:
            return baseURL.appendingPathComponent("configs")
        case .proxies:
            return baseURL.appendingPathComponent("proxies")
        case .proxyProviders:
            return baseURL.appendingPathComponent("providers/proxies")
        case .connections:
            return baseURL.appendingPathComponent("connections")
        case .traffic:
            return baseURL.appendingPathComponent("traffic")
        case let .changeProxy(group, _):
            return appendingEncodedPathSegment(
                group,
                to: baseURL.appendingPathComponent("proxies")
            )
        case let .groupDelay(group, url, timeout):
            let groupURL = appendingEncodedPathSegment(
                group,
                to: baseURL.appendingPathComponent("group")
            )
            var components = URLComponents(
                url: groupURL.appendingPathComponent("delay"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: "\(timeout)"),
            ]
            return components.url!
        case let .delayTest(proxy, url, timeout):
            let proxyURL = appendingEncodedPathSegment(
                proxy,
                to: baseURL.appendingPathComponent("proxies")
            )
            var components = URLComponents(
                url: proxyURL.appendingPathComponent("delay"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: "\(timeout)"),
            ]
            return components.url!
        case let .providerDelayTest(provider, proxy, url, timeout):
            let providerURL = appendingEncodedPathSegment(
                provider,
                to: baseURL.appendingPathComponent("providers/proxies")
            )
            let proxyURL = appendingEncodedPathSegment(proxy, to: providerURL)
            var components = URLComponents(
                url: proxyURL.appendingPathComponent("healthcheck"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: "\(timeout)"),
            ]
            return components.url!
        case let .closeConnection(id):
            return baseURL.appendingPathComponent("connections").appendingPathComponent(id)
        case .closeAllConnections:
            return baseURL.appendingPathComponent("connections")
        }
    }

    private func appendingEncodedPathSegment(_ segment: String, to url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet.urlPathAllowed
            .subtracting(CharacterSet(charactersIn: "/?#"))
        let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
        components.percentEncodedPath += "/\(encoded)"
        return components.url!
    }

    private func method(for endpoint: MihomoAPIEndpoint) -> String {
        switch endpoint {
        case .version, .configs, .proxies, .proxyProviders, .connections, .traffic,
             .groupDelay, .delayTest, .providerDelayTest:
            "GET"
        case .updateConfigs:
            "PATCH"
        case .changeProxy:
            "PUT"
        case .closeConnection, .closeAllConnections:
            "DELETE"
        }
    }

    private func body(for endpoint: MihomoAPIEndpoint) -> Data? {
        switch endpoint {
        case let .updateConfigs(mode, tunEnabled):
            var object: [String: Any] = [:]
            if let mode {
                object["mode"] = mode.rawValue
            }
            if let tunEnabled {
                object["tun"] = ["enable": tunEnabled]
            }
            return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        case let .changeProxy(_, proxy):
            return try? JSONSerialization.data(withJSONObject: ["name": proxy], options: [.sortedKeys])
        default:
            return nil
        }
    }
}

public struct MihomoAPIService: Sendable {
    public let requestBuilder: MihomoAPIRequest
    public let session: URLSession

    public init(requestBuilder: MihomoAPIRequest, session: URLSession? = nil) {
        self.requestBuilder = requestBuilder
        self.session = session ?? Self.controllerSession
    }

    private static let controllerSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        // Controller requests must keep working when the system proxy points at
        // a stalled core; routing them through that proxy prevents recovery.
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
        ]
        return URLSession(configuration: configuration)
    }()

    public func data(for endpoint: MihomoAPIEndpoint) async throws -> Data {
        let request = try requestBuilder.urlRequest(for: endpoint)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return data
    }

    public func lineDataStream(for endpoint: MihomoAPIEndpoint) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(bufferingPolicy: endpoint == .traffic ? .bufferingNewest(1) : .unbounded) { continuation in
            let streamTask = Task {
                do {
                    let request = try requestBuilder.urlRequest(for: endpoint)
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response: response, data: Data())
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(Data(line.utf8))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }

    public func proxyDelay(
        proxy: String,
        url: String,
        timeout: Int = LatencyTestPlan.defaultTimeoutMilliseconds,
        provider: String? = nil
    ) async -> Int? {
        do {
            if let provider {
                do {
                    let data = try await data(for: .providerDelayTest(
                        provider: provider, proxy: proxy, url: url, timeout: timeout
                    ))
                    return LatencyTestSettings.validMeasuredDelay(
                        try MihomoAPIDecoder.delay(from: data)
                    )
                } catch let MihomoAPIError.httpStatus(code, _) where code == 404 || code == 405 {
                    // Older controllers may only expose provider nodes in /proxies.
                }
            }
            try Task.checkCancellation()
            let data = try await data(
                for: .delayTest(proxy: proxy, url: url, timeout: timeout)
            )
            return LatencyTestSettings.validMeasuredDelay(
                try MihomoAPIDecoder.delay(from: data)
            )
        } catch {
            return nil
        }
    }

    public func groupDelays(
        group: String,
        url: String,
        timeout: Int = LatencyTestPlan.defaultTimeoutMilliseconds
    ) async throws -> [String: Int] {
        let data = try await data(
            for: .groupDelay(group: group, url: url, timeout: timeout)
        )
        return try MihomoAPIDecoder.groupDelays(from: data)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw MihomoAPIError.httpStatus(response.statusCode, message)
        }
    }
}

public enum MihomoAPIError: Error, LocalizedError {
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .httpStatus(code, message):
            "Mihomo API \(code): \(message)"
        }
    }
}

enum MihomoAPIDecoder {
    static func runtimeConfig(from data: Data) throws -> RuntimeConfigSnapshot {
        let response = try JSONDecoder().decode(RuntimeConfigResponse.self, from: data)
        return RuntimeConfigSnapshot(
            mixedPort: response.mixedPort,
            mode: OutboundMode(rawValue: response.mode?.lowercased() ?? "") ?? .rule,
            tunEnabled: response.tun?.enable ?? false
        )
    }

    static func proxyGroups(from data: Data, providerData: Data? = nil) throws -> [ProxyGroup] {
        let response = try JSONDecoder().decode(ProxiesResponse.self, from: data)
        // Mihomo 1.19.33 no longer includes provider-owned leaf metadata in /proxies.
        // Provider support remains optional for older controllers and local profiles.
        let providers = providerData.flatMap {
            try? JSONDecoder().decode(ProxyProvidersResponse.self, from: $0)
        }?.providers ?? [:]
        var providerNodes: [String: (provider: String, proxy: ProxyResponse)] = [:]
        for providerName in providers.keys.sorted() {
            for proxy in providers[providerName]?.proxies ?? [] {
                guard let name = proxy.name, providerNodes[name] == nil else { continue }
                providerNodes[name] = (providerName, proxy)
            }
        }
        return response.proxies
            .filter { $0.value.all?.isEmpty == false && $0.value.hidden != true }
            .keys
            .sorted()
            .compactMap { name in
                guard let proxy = response.proxies[name], let all = proxy.all else {
                    return nil
                }
                let now = proxy.now ?? all.first
                let nodes = all.filter { response.proxies[$0]?.hidden != true }.map { nodeName in
                    let region = regionCode(from: nodeName)
                    let metadata = response.proxies[nodeName] ?? providerNodes[nodeName]?.proxy
                    let latency = metadata?
                        .history?
                        .reversed()
                        .compactMap(\.delay)
                        .compactMap(LatencyTestSettings.validMeasuredDelay)
                        .first
                    return ProxyNode(
                        name: nodeName,
                        region: region,
                        latency: latency,
                        isSelected: nodeName == now,
                        isGroup: response.proxies[nodeName]?.all?.isEmpty == false,
                        providerName: response.proxies[nodeName] == nil
                            ? providerNodes[nodeName]?.provider : nil
                    )
                }
                return ProxyGroup(
                    name: name,
                    policy: proxy.type ?? "Selector",
                    kind: ProxyGroupKind(mihomoType: proxy.type),
                    testURL: proxy.testURL,
                    nodes: nodes
                )
            }
    }

    static func connections(from data: Data) throws -> [ConnectionEntry] {
        try connectionsSnapshot(from: data).entries
    }

    static func connectionsSnapshot(from data: Data) throws -> ConnectionsSnapshot {
        let response = try JSONDecoder().decode(ConnectionsResponse.self, from: data)
        let entries = response.connections.map { item in
            let host = item.metadata.host ?? item.metadata.destinationIP ?? item.metadata.destinationAddress ?? "Unknown"
            let port = item.metadata.destinationPort.map { ":\($0)" } ?? ""
            let rawRuleParts: [String?] = [item.rule, item.rulePayload]
            let ruleParts = rawRuleParts.compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            return ConnectionEntry(
                remoteID: item.id,
                host: "\(host)\(port)",
                rule: ruleParts.joined(separator: ","),
                chain: item.chains.joined(separator: " / "),
                upload: byteText(item.upload),
                download: byteText(item.download)
            )
        }
        return ConnectionsSnapshot(
            entries: entries,
            uploadTotal: response.uploadTotal ?? 0,
            downloadTotal: response.downloadTotal ?? 0
        )
    }

    static func traffic(from data: Data) throws -> TrafficSnapshot {
        let response = try JSONDecoder().decode(TrafficResponse.self, from: data)
        return TrafficSnapshot(up: response.up, down: response.down)
    }

    static func delay(from data: Data) throws -> Int {
        try JSONDecoder().decode(DelayResponse.self, from: data).delay
    }

    static func groupDelays(from data: Data) throws -> [String: Int] {
        try JSONDecoder().decode([String: Int].self, from: data)
    }

    static func byteText(_ bytes: Int) -> String {
        let value = Double(bytes)
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1f KB", value / 1_000)
        }
        return "\(bytes) B"
    }

    static func regionCode(from name: String) -> String {
        let upper = name.uppercased()
        let matches: [(String, String)] = [
            ("香港", "HK"), ("日本", "JP"), ("新加坡", "SG"), ("台湾", "TW"),
            ("韓国", "KR"), ("韩国", "KR"), ("美国", "US"), ("德國", "DE"),
            ("德国", "DE"), ("土耳其", "TR"),
            ("HONG KONG", "HK"), ("HK", "HK"), ("TOKYO", "JP"), ("JAPAN", "JP"), ("JP", "JP"),
            ("SINGAPORE", "SG"), ("SG", "SG"), ("TAIWAN", "TW"), ("TW", "TW"),
            ("KOREA", "KR"), ("SEOUL", "KR"), ("US", "US"), ("LOS ANGELES", "US"),
        ]
        return matches.first { upper.contains($0.0) }?.1 ?? "Proxy"
    }

}

public struct TrafficSnapshot: Equatable, Sendable {
    public let up: Int
    public let down: Int

    public init(up: Int, down: Int) {
        self.up = up
        self.down = down
    }
}

public struct RuntimeConfigSnapshot: Equatable, Sendable {
    public let mixedPort: Int?
    public let mode: OutboundMode
    public let tunEnabled: Bool

    public init(mixedPort: Int?, mode: OutboundMode, tunEnabled: Bool) {
        self.mixedPort = mixedPort
        self.mode = mode
        self.tunEnabled = tunEnabled
    }
}

struct ConnectionsSnapshot {
    let entries: [ConnectionEntry]
    let uploadTotal: Int
    let downloadTotal: Int

    init(entries: [ConnectionEntry], uploadTotal: Int, downloadTotal: Int) {
        self.entries = entries
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
    }
}

private struct RuntimeConfigResponse: Decodable {
    let mixedPort: Int?
    let mode: String?
    let tun: RuntimeTunResponse?

    enum CodingKeys: String, CodingKey {
        case mixedPort = "mixed-port"
        case mode
        case tun
    }
}

private struct RuntimeTunResponse: Decodable {
    let enable: Bool?
}

private struct ProxiesResponse: Decodable {
    let proxies: [String: ProxyResponse]
}

private struct ProxyProvidersResponse: Decodable {
    let providers: [String: ProxyProviderResponse]
}

private struct ProxyProviderResponse: Decodable {
    let proxies: [ProxyResponse]?
}

private struct ProxyResponse: Decodable {
    let name: String?
    let type: String?
    let now: String?
    let all: [String]?
    let history: [ProxyHistory]?
    let testURL: String?
    let hidden: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case now
        case all
        case history
        case testURL = "testUrl"
        case hidden
    }
}

private struct ProxyHistory: Decodable {
    let delay: Int?
}

private struct ConnectionsResponse: Decodable {
    let downloadTotal: Int?
    let uploadTotal: Int?
    let connections: [ConnectionResponse]
}

private struct ConnectionResponse: Decodable {
    let id: String?
    let metadata: ConnectionMetadata
    let upload: Int
    let download: Int
    let chains: [String]
    let rule: String?
    let rulePayload: String?
}

private struct ConnectionMetadata: Decodable {
    let host: String?
    let destinationIP: String?
    let destinationAddress: String?
    let destinationPort: String?

    enum CodingKeys: String, CodingKey {
        case host
        case destinationIP
        case destinationAddress
        case destinationPort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        destinationIP = try container.decodeIfPresent(String.self, forKey: .destinationIP)
        destinationAddress = try container.decodeIfPresent(String.self, forKey: .destinationAddress)
        if let stringPort = try? container.decodeIfPresent(String.self, forKey: .destinationPort) {
            destinationPort = stringPort
        } else if let intPort = try? container.decodeIfPresent(Int.self, forKey: .destinationPort) {
            destinationPort = "\(intPort)"
        } else {
            destinationPort = nil
        }
    }
}

private struct TrafficResponse: Decodable {
    let up: Int
    let down: Int
}

private struct DelayResponse: Decodable {
    let delay: Int
}
