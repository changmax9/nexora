import Foundation

public enum WebsiteProbeRoute: String, CaseIterable, Identifiable, Sendable {
    case direct, nexora
    public var id: Self { self }
}

public struct WebsiteProxyEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    var url: URL? {
        guard (1...65535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }
}

public enum WebsiteProbeFailure: String, Equatable, Sendable {
    case dns, connection, tls, timeout, proxyUnavailable, proxyAuthentication, request, cancelled

    var messageKey: AppString {
        switch self {
        case .dns: .websiteDNSFailure
        case .connection: .websiteConnectionFailure
        case .tls: .websiteTLSFailure
        case .timeout: .websiteTimeout
        case .proxyUnavailable: .websiteProxyInactive
        case .proxyAuthentication: .websiteProxyAuthentication
        case .request: .websiteRequestFailure
        case .cancelled: .websiteCancelled
        }
    }
}

public struct WebsiteProbeResult: Equatable, Sendable {
    public let route: WebsiteProbeRoute
    public let statusCode: Int?
    public let latencyMilliseconds: Int?
    public let dnsMilliseconds: Int?
    public let failure: WebsiteProbeFailure?

    public init(route: WebsiteProbeRoute, statusCode: Int? = nil, latencyMilliseconds: Int? = nil,
                dnsMilliseconds: Int? = nil, failure: WebsiteProbeFailure? = nil) {
        self.route = route
        self.statusCode = statusCode
        self.latencyMilliseconds = latencyMilliseconds
        self.dnsMilliseconds = dnsMilliseconds
        self.failure = failure
    }

    public var receivedResponse: Bool { statusCode != nil && failure == nil }
    public var isSuccessfulHTTP: Bool { receivedResponse && statusCode.map { (200..<400).contains($0) } == true }

    func statusText(language: AppLanguage) -> String {
        if let failure { return language.text(failure.messageKey) }
        return statusCode.map { "HTTP \($0)" } ?? language.text(.websiteRequestFailure)
    }
}

public struct WebsiteComparisonContext: Equatable, Sendable {
    public let proxy: WebsiteProxyEndpoint?
    public let mode: OutboundMode
    public let hasSystemTunnel: Bool

    public init(proxy: WebsiteProxyEndpoint?, mode: OutboundMode, hasSystemTunnel: Bool) {
        self.proxy = proxy
        self.mode = mode
        self.hasSystemTunnel = hasSystemTunnel
    }
}

public struct WebsiteComparison: Equatable, Sendable {
    public let url: URL
    public let context: WebsiteComparisonContext
    public let results: [WebsiteProbeResult]
    public let date: Date

    func copyText(language: AppLanguage) -> String {
        // Query strings can contain private tokens. Keep them out of copied reports.
        var displayURL = URLComponents(url: url, resolvingAgainstBaseURL: false)
        displayURL?.query = nil
        displayURL?.fragment = nil
        var lines = [language.text(.websiteComparisonTitle), displayURL?.string ?? url.host ?? "",
                     date.formatted(date: .numeric, time: .standard), language.text(context.mode.titleKey)]
        if context.hasSystemTunnel { lines.append(language.text(.websiteTunnelWarning)) }
        for result in results {
            let title = language.text(result.route == .direct ? .websiteDirectRoute : .websiteNexoraRoute)
            let timing = result.latencyMilliseconds.map { " · \($0) ms" } ?? ""
            lines.append("\(title): \(result.statusText(language: language))\(timing)")
        }
        return lines.joined(separator: "\n")
    }
}

public enum WebsiteURLInput {
    public static func normalized(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2048,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              var components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              components.user == nil, components.password == nil else { throw InputError.invalid }
        components.scheme = components.scheme?.lowercased()
        components.fragment = nil
        guard let url = components.url else { throw InputError.invalid }
        return url
    }

    public enum InputError: Error { case invalid }
}
