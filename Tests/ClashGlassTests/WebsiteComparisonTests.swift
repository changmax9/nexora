import Darwin
import Foundation
import Synchronization
import Testing
@testable import ClashGlassCore

@Suite(.serialized)
struct WebsiteComparisonTests {
    @Test func liveWebsiteComparisonWhenExplicitlyRequested() async throws {
        guard let rawPort = ProcessInfo.processInfo.environment["NEXORA_WEBSITE_LIVE_PROXY_PORT"],
              let port = Int(rawPort) else { return }
        let context = WebsiteComparisonContext(proxy: .init(host: "127.0.0.1", port: port), mode: .rule, hasSystemTunnel: false)
        for host in ["www.baidu.com", "chatgpt.com"] {
            let result = await WebsiteComparisonService().compare(url: URL(string: "https://\(host)")!, context: context)
            #expect(result.results[1].receivedResponse)
            if host == "www.baidu.com" { #expect(result.results[0].receivedResponse) }
            print("Website comparison \(host): " + result.results.map {
                "\($0.route.rawValue) HTTP \($0.statusCode ?? 0), \($0.latencyMilliseconds ?? 0)ms, \($0.failure?.rawValue ?? "response")"
            }.joined(separator: "; "))
        }
    }

    @Test(arguments: ["example.com/path?q=1", "https://example.com/path?q=1#section"])
    func normalizesPublicURLsAndDropsFragments(input: String) throws {
        #expect(try WebsiteURLInput.normalized(input).absoluteString == "https://example.com/path?q=1")
    }

    @Test(arguments: ["", "ftp://example.com", "file:///tmp/a", "https://user:password@example.com",
                      "https://example.com/\nheader", "not a website", String(repeating: "a", count: 2049)])
    func rejectsUnsupportedOrCredentialBearingInput(input: String) {
        #expect(throws: WebsiteURLInput.InputError.self) { try WebsiteURLInput.normalized(input) }
    }

    @Test func routesAreExplicitAndCannotInheritCurlConfiguration() throws {
        let url = try WebsiteURLInput.normalized("https://example.com/?q=a;b")
        let direct = WebsiteComparisonService.arguments(url: url, proxy: nil)
        let forwarded = WebsiteComparisonService.arguments(url: url, proxy: .init(host: "127.0.0.1", port: 7890))
        #expect(direct.first == "--disable")
        #expect(Array(direct.suffix(6)) == ["--noproxy", "*", "--proxy", "", "--url", url.absoluteString])
        #expect(Array(forwarded.suffix(6)) == ["--noproxy", "", "--proxy", "http://127.0.0.1:7890", "--url", url.absoluteString])
        #expect(!direct.contains("--insecure"))
        #expect(direct.contains("=http,https"))
    }

    @Test(arguments: [200, 301, 403, 404, 500])
    func HTTPResponsesAreNotReportedAsNetworkDisconnects(status: Int) {
        let result = WebsiteComparisonService.result(data: metrics(status: status), exitCode: 0, route: .direct)
        #expect(result.receivedResponse)
        #expect(result.isSuccessfulHTTP == (200..<400).contains(status))
        #expect(result.latencyMilliseconds == 1250)
        #expect(result.dnsMilliseconds == 25)
    }

    @Test(arguments: [(Int32(6), WebsiteProbeFailure.dns), (7, .connection), (28, .timeout), (60, .tls)])
    func transportFailuresRemainDistinct(caseValue: (Int32, WebsiteProbeFailure)) {
        let result = WebsiteComparisonService.result(data: metrics(status: 0), exitCode: caseValue.0, route: .direct)
        #expect(!result.receivedResponse)
        #expect(result.failure == caseValue.1)
    }

    @Test func proxyAuthenticationAndBoundedGETAreClassifiedCorrectly() {
        let auth = WebsiteComparisonService.result(data: metrics(status: 0, connect: 407), exitCode: 56, route: .nexora)
        #expect(auth.failure == .proxyAuthentication)
        #expect(auth.dnsMilliseconds == nil)
        let limited = WebsiteComparisonService.result(data: metrics(status: 200), exitCode: 63, route: .direct)
        #expect(limited.receivedResponse)
        let timedOut = WebsiteComparisonService.result(data: metrics(status: 200), exitCode: 28, route: .direct)
        #expect(timedOut.failure == .timeout)
    }

    @Test func bothRoutesStartConcurrently() async throws {
        let gate = WebsiteProbeGate()
        let service = WebsiteComparisonService(probe: { _, route, _ in
            await gate.arriveAndWait()
            return .init(route: route, statusCode: 200)
        })
        let task = Task { await service.compare(url: URL(string: "https://example.com")!, context: context(proxy: true)) }
        let arrived = await gate.waitForArrivals(2)
        await gate.release()
        let result = await task.value
        #expect(arrived == 2)
        #expect(result.results.map(\.route) == [.direct, .nexora])
    }

    @Test func missingProxyDoesNotStartOrReconfigureAnything() async {
        let calls = Mutex<[WebsiteProbeRoute]>([])
        let service = WebsiteComparisonService(probe: { _, route, _ in
            calls.withLock { $0.append(route) }
            return .init(route: route, statusCode: 200)
        })
        let result = await service.compare(url: URL(string: "https://example.com")!, context: context())
        #expect(calls.withLock { $0 } == [.direct])
        #expect(result.results[1].failure == .proxyUnavailable)
    }

    @Test func HEADRejectionFallsBackToASmallGET() async throws {
        let fixture = try WebsiteCurlFixture(script: """
        is_head=no
        for arg in "$@"; do if [ "$arg" = "--head" ]; then is_head=yes; fi; done
        root="$(dirname "$0")"
        echo "$is_head" >> "$root/methods"
        if [ "$is_head" = yes ]; then
          echo '{"status":"405","connect":"000","dns":0.025,"total":0.1}'
        else
          echo '{"status":"200","connect":"000","dns":0.025,"total":0.2}'
        fi
        """)
        defer { fixture.cleanup() }
        let result = await WebsiteComparisonService(executableURL: fixture.executable)
            .compare(url: URL(string: "https://example.com")!, context: context())
        #expect(result.results[0].statusCode == 200)
        #expect(result.results[0].latencyMilliseconds == 300)
        #expect(try String(contentsOf: fixture.directory.appendingPathComponent("methods"), encoding: .utf8) == "yes\nno\n")
        let bounded = WebsiteComparisonService.arguments(url: URL(string: "https://example.com")!, proxy: nil, head: false)
        #expect(bounded.contains("--max-filesize"))
        #expect(bounded.contains("--range"))
    }

    @MainActor
    @Test func cancelTerminatesTheProbeAndNeverPublishesItsResult() async throws {
        let fixture = try WebsiteCurlFixture(script: """
        root="$(dirname "$0")"
        echo $$ > "$root/pid"
        exec /bin/sleep 60
        """)
        let store = WebsiteComparisonStore(service: .init(executableURL: fixture.executable))
        defer { store.cancel(); fixture.cleanup() }
        store.input = "example.com"
        let task = Task { await store.run(context: context()) }
        let pidURL = fixture.directory.appendingPathComponent("pid")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: pidURL.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        store.cancel()
        await task.value
        #expect(!store.isRunning)
        #expect(store.result == nil)
        #expect(store.wasCancelled)
        let pid = try Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        if let pid { #expect(Darwin.kill(pid, 0) != 0) }
    }

    @MainActor
    @Test func anOldCancelledRequestCannotReplaceANewerResult() async {
        let gate = WebsiteProbeGate()
        let store = WebsiteComparisonStore(service: .init(probe: { url, route, _ in
            if url.host == "first.example" { await gate.arriveAndWait() }
            return .init(route: route, statusCode: 200)
        }))
        store.input = "first.example"
        let old = Task { await store.run(context: context()) }
        _ = await gate.waitForArrivals(1)
        store.cancel()
        store.input = "second.example"
        await store.run(context: context())
        await gate.release()
        await old.value
        #expect(store.result?.url.host == "second.example")
        #expect(!store.isRunning)
        store.input = "third.example"
        #expect(store.isStale)
    }

    @MainActor
    @Test func inputErrorsAndNetworkChangesInvalidateExistingEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let identifier = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: identifier))
        let store = AppStore(
            coreService: MihomoCoreService(coreBinaryURL: nil, privilegedTUN: nil),
            profileRepository: ManagedProfileRepository(rootURL: directory),
            networkIdentityService: NetworkIdentityService(systemTunnelDetector: { false }),
            websiteComparisonService: .init(probe: { _, route, _ in .init(route: route, statusCode: 200) }),
            userDefaults: defaults, automaticallyMonitorsRuntime: false
        )
        defer {
            store.shutdownForApplicationTermination()
            defaults.removePersistentDomain(forName: identifier)
            try? FileManager.default.removeItem(at: directory)
        }
        store.websiteComparison.input = "example.com"
        await store.compareWebsite()
        #expect(store.websiteComparison.result != nil)
        store.isTunEnabled = true // Model change only; no privileged API is called.
        #expect(store.websiteComparison.isStale)
        store.websiteComparison.input = "ftp://example.com"
        await store.compareWebsite()
        #expect(store.websiteComparison.isInputInvalid)
        #expect(!store.isCoreRunning)
    }

    @Test func copiedEvidenceKeepsTheTunnelCaveatAndRedactsQueryTokens() async {
        let service = WebsiteComparisonService(probe: { _, route, _ in .init(route: route, statusCode: 200) })
        let result = await service.compare(url: URL(string: "https://example.com/path?token=private-token")!,
                                           context: .init(proxy: nil, mode: .rule, hasSystemTunnel: true))
        let copy = result.copyText(language: .simplifiedChinese)
        #expect(copy.contains(AppLanguage.simplifiedChinese.text(.websiteTunnelWarning)))
        #expect(!copy.contains("private-token"))
        #expect(!copy.contains("?token"))
    }

    @Test func newLabelsHaveTranslationsForEverySupportedLanguage() {
        for language in AppLanguage.selectableCases where language != .system {
            for key in AppString.allCases where key.rawValue.hasPrefix("website") {
                #expect(AppLocalization.hasTranslation(key, language: language))
            }
        }
    }
}

private func context(proxy: Bool = false) -> WebsiteComparisonContext {
    .init(proxy: proxy ? .init(host: "127.0.0.1", port: 7890) : nil, mode: .rule, hasSystemTunnel: false)
}

private func metrics(status: Int, connect: Int = 0) -> Data {
    Data("{\"status\":\"\(status)\",\"connect\":\"\(connect)\",\"dns\":0.025,\"total\":1.25}".utf8)
}

private actor WebsiteProbeGate {
    private var arrivals = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndWait() async {
        arrivals += 1
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitForArrivals(_ expected: Int) async -> Int {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while arrivals < expected, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return arrivals
    }

    func release() {
        released = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}

private struct WebsiteCurlFixture {
    let directory: URL
    let executable: URL

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        executable = directory.appendingPathComponent("fake-curl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
