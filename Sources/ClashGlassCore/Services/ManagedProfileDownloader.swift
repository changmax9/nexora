import Foundation
import Yams

public enum ManagedProfileDownloadError: Error, Equatable, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse
    case notConfiguration

    public var errorDescription: String? {
        message(language: .english)
    }

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidURL:
            language.text(.invalidProfileURL)
        case .invalidResponse:
            language.text(.profileDownloadInvalidResponse)
        case let .httpStatus(status):
            String(format: language.text(.profileDownloadHTTPErrorFormat), status)
        case .emptyResponse:
            language.text(.profileDownloadEmpty)
        case .notConfiguration:
            language.text(.profileDownloadNotConfiguration)
        }
    }
}

public struct ManagedProfileDownload: Sendable {
    public let data: Data
    public let name: String
    public let trafficUsage: ProfileTrafficUsage?
}

public struct ManagedProfileDownloader: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func configurationURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              !host.contains(where: \.isWhitespace) else {
            throw ManagedProfileDownloadError.invalidURL
        }
        return url
    }

    public func download(from sourceURL: URL) async throws -> ManagedProfileDownload {
        let url = try Self.configurationURL(from: sourceURL.absoluteString)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Subscription servers use the client identifier to choose YAML over a generic node list.
        request.setValue("Clash.Meta", forHTTPHeaderField: "User-Agent")
        request.setValue("application/yaml, text/yaml, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw ManagedProfileDownloadError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ManagedProfileDownloadError.httpStatus(response.statusCode)
        }
        guard !data.isEmpty else {
            throw ManagedProfileDownloadError.emptyResponse
        }

        // Some providers return HTTP 200 with a health message or an error page.
        // MIME types are unreliable: valid subscription YAML can be labeled text/html.
        let configurationKeys: Set<String> = [
            "proxies", "proxy-providers", "proxy-groups", "rules", "rule-providers",
            "mixed-port", "port", "socks-port", "redir-port", "tproxy-port", "tun", "dns",
            "mode", "external-controller",
        ]
        guard let yaml = String(data: data, encoding: .utf8),
              let document = try? Yams.load(yaml: yaml) as? [String: Any],
              !configurationKeys.isDisjoint(with: document.keys) else {
            throw ManagedProfileDownloadError.notConfiguration
        }

        return ManagedProfileDownload(
            data: data,
            name: Self.profileName(response: response, url: url),
            trafficUsage: ProfileTrafficUsage(
                subscriptionUserInfo: response.value(forHTTPHeaderField: "Subscription-Userinfo")
            )
        )
    }

    static func profileName(response: HTTPURLResponse, url: URL) -> String {
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition") {
            if let encoded = dispositionValue("filename*", in: disposition) {
                let parts = encoded.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3, ["utf-8", "us-ascii"].contains(parts[0].lowercased()),
                   let decoded = String(parts[2]).removingPercentEncoding,
                   let name = displayName(filename: decoded) {
                    return name
                }
            }
            if let filename = dispositionValue("filename", in: disposition),
               let name = displayName(filename: filename) {
                return name
            }
        }
        if ["yaml", "yml"].contains(url.pathExtension.lowercased()),
           let name = displayName(filename: url.lastPathComponent) {
            return name
        }
        return url.host ?? "Profile"
    }

    private static func dispositionValue(_ key: String, in header: String) -> String? {
        let pattern = #"(?i)(?:^|;)\s*"# + NSRegularExpression.escapedPattern(for: key)
            + #"\s*=\s*(?:"([^"]*)"|([^;]*))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else { return nil }
        for group in 1...2 {
            if let range = Range(match.range(at: group), in: header) {
                return String(header[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func displayName(filename: String) -> String? {
        let cleaned = filename.components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: "\\", with: "/")
        let fileURL = URL(fileURLWithPath: cleaned)
        let name = (["yaml", "yml"].contains(fileURL.pathExtension.lowercased())
            ? fileURL.deletingPathExtension().lastPathComponent : fileURL.lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || [".", "..", "~"].contains(name) ? nil : name
    }
}
