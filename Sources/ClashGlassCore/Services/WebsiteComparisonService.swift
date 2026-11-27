import Darwin
import Foundation

public struct WebsiteComparisonService: Sendable {
    private let executableURL: URL
    private let probeOverride: (@Sendable (URL, WebsiteProbeRoute, WebsiteProxyEndpoint?) async -> WebsiteProbeResult)?

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/curl")) {
        self.executableURL = executableURL
        probeOverride = nil
    }

    init(probe: @escaping @Sendable (URL, WebsiteProbeRoute, WebsiteProxyEndpoint?) async -> WebsiteProbeResult) {
        executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        probeOverride = probe
    }

    public func compare(url: URL, context: WebsiteComparisonContext) async -> WebsiteComparison {
        async let direct = probe(url: url, route: .direct, proxy: nil)
        async let nexora = probeNexora(url: url, proxy: context.proxy)
        return await WebsiteComparison(url: url, context: context, results: [direct, nexora], date: Date())
    }

    private func probeNexora(url: URL, proxy: WebsiteProxyEndpoint?) async -> WebsiteProbeResult {
        guard let proxy, proxy.url != nil else { return .init(route: .nexora, failure: .proxyUnavailable) }
        return await probe(url: url, route: .nexora, proxy: proxy)
    }

    private func probe(url: URL, route: WebsiteProbeRoute, proxy: WebsiteProxyEndpoint?) async -> WebsiteProbeResult {
        if let probeOverride { return await probeOverride(url, route, proxy) }
        do {
            try Task.checkCancellation()
            let output = try await WebsiteProbeProcess().run(
                executable: executableURL, arguments: Self.arguments(url: url, proxy: proxy)
            )
            let first = Self.result(data: output.data, exitCode: output.exitCode, route: route)
            // Some sites reject HEAD although ordinary browsing works. Fall back
            // to a bounded GET; never download an arbitrary full response body.
            guard [405, 501].contains(first.statusCode ?? 0), first.failure == nil else { return first }
            try Task.checkCancellation()
            let remaining = max(0.2, 8 - Double(first.latencyMilliseconds ?? 0) / 1000)
            let fallback = try await WebsiteProbeProcess().run(
                executable: executableURL,
                arguments: Self.arguments(url: url, proxy: proxy, head: false, timeout: remaining)
            )
            let result = Self.result(data: fallback.data, exitCode: fallback.exitCode, route: route)
            return .init(route: route, statusCode: result.statusCode,
                         latencyMilliseconds: (first.latencyMilliseconds ?? 0) + (result.latencyMilliseconds ?? 0),
                         dnsMilliseconds: result.dnsMilliseconds, failure: result.failure)
        } catch is CancellationError {
            return .init(route: route, failure: .cancelled)
        } catch {
            return .init(route: route, failure: .request)
        }
    }

    static func arguments(url: URL, proxy: WebsiteProxyEndpoint?, head: Bool = true, timeout: Double = 8) -> [String] {
        var arguments = [
            "--disable", "--silent", "--show-error", "--globoff",
            "--location", "--max-redirs", "5", "--proto", "=http,https", "--proto-redir", "=http,https",
            "--connect-timeout", "5", "--max-time", String(timeout), "--output", "/dev/null",
            "--write-out", #"{"status":"%{http_code}","connect":"%{http_connect}","dns":%{time_namelookup},"total":%{time_total}}"#,
        ]
        if head { arguments.append("--head") }
        else { arguments += ["--range", "0-0", "--max-filesize", "262144"] }
        if let proxy, let proxyURL = proxy.url {
            arguments += ["--noproxy", "", "--proxy", proxyURL.absoluteString]
        } else {
            arguments += ["--noproxy", "*", "--proxy", ""]
        }
        arguments += ["--url", url.absoluteString]
        return arguments
    }

    static func result(data: Data, exitCode: Int32, route: WebsiteProbeRoute) -> WebsiteProbeResult {
        struct Metrics: Decodable { let status: String; let connect: String; let dns: Double; let total: Double }
        guard let metrics = try? JSONDecoder().decode(Metrics.self, from: data),
              metrics.total.isFinite, metrics.dns.isFinite else { return .init(route: route, failure: .request) }
        let code = Int(metrics.status) ?? 0
        let status = (100...599).contains(code) ? code : nil
        let failure: WebsiteProbeFailure?
        switch exitCode {
        case 0: failure = status == nil ? .request : nil
        case 63 where status != nil: failure = nil // Bounded GET already received HTTP headers.
        case 5, 6: failure = .dns
        case 7: failure = .connection
        case 28: failure = .timeout
        case 35, 51, 58, 60, 77, 83, 90, 91: failure = .tls
        default: failure = Int(metrics.connect) == 407 ? .proxyAuthentication : .request
        }
        return .init(route: route, statusCode: status,
                     latencyMilliseconds: Int(min(86_400, max(0, metrics.total)) * 1000),
                     dnsMilliseconds: route == .direct ? Int(min(86_400, max(0, metrics.dns)) * 1000) : nil,
                     failure: failure)
    }
}

/// Cancellation terminates only this probe process, never the running core.
private final class WebsiteProbeProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    struct Output: Sendable { let data: Data; let exitCode: Int32 }

    func run(executable: URL, arguments: [String]) async throws -> Output {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { [self] in
                let process = Process()
                let output = Pipe()
                // curl's stderr may contain the submitted URL; do not retain or log it.
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                try lock.withLock {
                    guard !cancelled else { throw CancellationError() }
                    self.process = process
                    try process.run()
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                try lock.withLock {
                    self.process = nil
                    if cancelled { throw CancellationError() }
                }
                return Output(data: data, exitCode: process.terminationStatus)
            }.value
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        let running = lock.withLock {
            cancelled = true
            return process
        }
        guard let running, running.isRunning else { return }
        running.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            if running.isRunning { Darwin.kill(running.processIdentifier, SIGKILL) }
        }
    }
}
