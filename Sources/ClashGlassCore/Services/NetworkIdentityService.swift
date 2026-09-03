import CFNetwork
import Darwin
import Foundation

public struct NetworkIdentity: Equatable, Sendable {
    public let ip: String
    public let countryCode: String
    public let countryName: String

    public init(ip: String, countryCode: String, countryName: String) {
        self.ip = ip
        self.countryCode = countryCode.uppercased()
        self.countryName = countryName
    }

    public var flagEmoji: String {
        let scalars = countryCode.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard scalar.value >= 65, scalar.value <= 90 else {
                return nil
            }
            return UnicodeScalar(127_397 + scalar.value)
        }
        guard scalars.count == 2 else {
            return "🌐"
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

public enum NetworkAddressPolicy {
    public static func isIPv4(_ address: String) -> Bool {
        var storage = in_addr()
        return address.withCString {
            inet_pton(AF_INET, $0, &storage) == 1
        }
    }
}

public enum SystemTunnelRouteDetector {
    public static func isActive() -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-rn", "-f", "inet"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let routingTable = String(data: data, encoding: .utf8) else {
            return false
        }
        return isActive(in: routingTable)
    }

    public static func isActive(in routingTable: String) -> Bool {
        routingTable.split(whereSeparator: \.isNewline).contains { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 4,
                  let networkInterface = fields.last,
                  networkInterface.hasPrefix("utun") else {
                return false
            }

            let destination = String(fields[0])
            let gateway = String(fields[1])
            guard gateway.hasPrefix("198.18."),
                  !destination.hasPrefix("198.18.") else {
                return false
            }
            return true
        }
    }
}

public enum NetworkIdentityDecoder {
    public static func decode(_ data: Data) throws -> NetworkIdentity {
        let response = try JSONDecoder().decode(NetworkIdentityResponse.self, from: data)
        guard response.success != false,
              let ip = response.ip,
              let countryCode = response.countryCode,
              let country = response.country else {
            throw NetworkIdentityError.invalidResponse(response.message)
        }
        return NetworkIdentity(ip: ip, countryCode: countryCode, countryName: country)
    }
}

public struct DirectNetworkIdentityFetcher: Sendable {
    public let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/curl")) {
        self.executableURL = executableURL
    }

    public func fetch(endpoint: URL) async throws -> NetworkIdentity {
        let executableURL = executableURL
        return try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.executableURL = executableURL
            process.arguments = [
                "--silent",
                "--show-error",
                "--fail",
                "--location",
                "--max-time", "8",
                "--ipv4",
                "--noproxy", "*",
                "--proxy", "",
                endpoint.absoluteString,
            ]
            process.standardOutput = output
            process.standardError = errorOutput

            do {
                try process.run()
            } catch {
                throw NetworkIdentityError.commandFailed(error.localizedDescription)
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw NetworkIdentityError.commandFailed(
                    message?.isEmpty == false ? message! : "Direct IP lookup failed."
                )
            }
            return try NetworkIdentityDecoder.decode(data)
        }.value
    }
}

public struct NetworkIdentityService: Sendable {
    public let endpoint: URL
    public let ipv4Endpoint: URL
    public let directFetcher: DirectNetworkIdentityFetcher
    public let systemTunnelDetector: @Sendable () -> Bool

    public init(
        endpoint: URL = URL(string: "https://ipwho.is/")!,
        ipv4Endpoint: URL = URL(string: "https://api4.ipify.org?format=json")!,
        directFetcher: DirectNetworkIdentityFetcher = DirectNetworkIdentityFetcher(),
        systemTunnelDetector: @escaping @Sendable () -> Bool = SystemTunnelRouteDetector.isActive
    ) {
        self.endpoint = endpoint
        self.ipv4Endpoint = ipv4Endpoint
        self.directFetcher = directFetcher
        self.systemTunnelDetector = systemTunnelDetector
    }

    public func fetchDirect() async throws -> NetworkIdentity {
        try await directFetcher.fetch(endpoint: endpoint)
    }

    public func fetchViaProxy(host: String, port: Int) async throws -> NetworkIdentity {
        let proxy = (host, port)
        let ipv4Data = try await fetchData(from: ipv4Endpoint, proxy: proxy)
        let ipv4 = try JSONDecoder().decode(IPv4LookupResponse.self, from: ipv4Data).ip
        guard NetworkAddressPolicy.isIPv4(ipv4) else {
            throw NetworkIdentityError.invalidResponse("The proxy did not return an IPv4 address.")
        }
        let identityURL = endpoint.appendingPathComponent(ipv4)
        let identityData = try await fetchData(from: identityURL, proxy: proxy)
        return try NetworkIdentityDecoder.decode(identityData)
    }

    public func hasActiveSystemTunnel() async -> Bool {
        let detector = systemTunnelDetector
        return await Task.detached(priority: .utility) {
            detector()
        }.value
    }

    public func localIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  interface.ifa_flags & UInt32(IFF_UP) != 0 else {
                continue
            }
            var socketAddress = address.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                &socketAddress,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }
            let hostBytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            candidates.append((
                name: String(cString: interface.ifa_name),
                address: String(decoding: hostBytes, as: UTF8.self)
            ))
        }

        let preferredNames = ["en0", "en1", "bridge0"]
        for name in preferredNames {
            if let candidate = candidates.first(where: { $0.name == name }) {
                return candidate.address
            }
        }
        return candidates.first?.address
    }

    private func fetchData(
        from url: URL,
        proxy: (host: String, port: Int)?
    ) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        if let proxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                kCFNetworkProxiesHTTPSPort as String: proxy.port,
            ]
        } else {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 0,
                kCFNetworkProxiesHTTPSEnable as String: 0,
                kCFNetworkProxiesSOCKSEnable as String: 0,
            ]
        }
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw NetworkIdentityError.invalidResponse(nil)
        }
        return data
    }
}

public enum NetworkIdentityError: Error, LocalizedError, Equatable {
    case invalidResponse(String?)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidResponse(message):
            message ?? "Could not determine the current network location."
        case let .commandFailed(message):
            message
        }
    }
}

private struct NetworkIdentityResponse: Decodable {
    let success: Bool?
    let message: String?
    let ip: String?
    let country: String?
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case ip
        case country
        case countryCode = "country_code"
    }
}

private struct IPv4LookupResponse: Decodable {
    let ip: String
}
