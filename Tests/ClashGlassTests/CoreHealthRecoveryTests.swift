import CFNetwork
import Foundation
import Testing
@testable import ClashGlassCore

@Test func controllerRequestsHaveShortHealthDeadlinesWithoutShorteningLatencyTests() throws {
    let builder = MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!)
    #expect(try builder.urlRequest(for: .version).timeoutInterval == 2)
    #expect(try builder.urlRequest(for: .configs).timeoutInterval == 5)
    #expect(try builder.urlRequest(for: .delayTest(proxy: "node", url: "https://example.com", timeout: 10_000)).timeoutInterval == 12)
    #expect(try builder.urlRequest(for: .providerDelayTest(provider: "airport", proxy: "node", url: "https://example.com", timeout: 10_000)).timeoutInterval == 12)
    #expect(try builder.urlRequest(for: .traffic).timeoutInterval == 60)
    #expect(try builder.urlRequest(for: .version).cachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func controllerSessionBypassesABrokenSystemProxyAndCachedControllerResponses() {
    let service = MihomoAPIService(requestBuilder: MihomoAPIRequest(baseURL: URL(string: "http://127.0.0.1:9090")!))
    let configuration = service.session.configuration
    let proxies = configuration.connectionProxyDictionary
    #expect((proxies?[kCFNetworkProxiesHTTPEnable as String] as? Int) == 0)
    #expect((proxies?[kCFNetworkProxiesHTTPSEnable as String] as? Int) == 0)
    #expect((proxies?[kCFNetworkProxiesSOCKSEnable as String] as? Int) == 0)
    #expect(configuration.urlCache == nil)
}

@Test func repeatedCoreOutputRetainsOnlyTwoBoundedLogFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NexoraBoundedLog-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let logURL = directory.appendingPathComponent("mihomo.log")
    let sink = CoreOutputSink(logURL: logURL, maximumFileBytes: 1_024)
    let first = Data(repeating: 65, count: 1_024)
    let middle = Data(repeating: 66, count: 1_024)
    let newest = Data(repeating: 67, count: 1_024)
    // A single output chunk can exceed the disk budget; it must rotate too.
    sink.append(first + middle + newest)
    sink.finish()

    #expect(try Data(contentsOf: logURL) == newest)
    #expect(try Data(contentsOf: logURL.appendingPathExtension("previous")) == middle)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    #expect(sink.text == String(decoding: first + middle + newest, as: UTF8.self))
}

@Test func restartingCorePreservesOnlyTheTailOfAnOlderUnboundedLog() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NexoraPreviousLog-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let logURL = directory.appendingPathComponent("mihomo.log")
    let lastFailure = Data("level=error msg=\"previous core failed\"\n".utf8)
    let previousLog = Data(repeating: 65, count: 5_000) + lastFailure
    try previousLog.write(to: logURL)
    let sink = CoreOutputSink(logURL: logURL, maximumFileBytes: 1_024)
    sink.append(Data("new run\n".utf8))
    sink.finish()

    #expect(try Data(contentsOf: logURL) == Data("new run\n".utf8))
    #expect(try Data(contentsOf: logURL.appendingPathExtension("previous")) == Data(previousLog.suffix(1_024)))
}

@MainActor
@Test(arguments: [false, true])
func stoppingOrCancelingDuringValidationCannotLaunchAnOrphanCore(cancel: Bool) async throws {
    let fixture = try CoreLaunchRaceFixture()
    defer { fixture.cleanup() }
    let launch = Task { await fixture.core.start(configPath: fixture.config.path, runtimeDirectoryURL: fixture.directory) }
    try await fixture.waitForFile("validation-started")
    if cancel {
        launch.cancel()
    } else {
        await fixture.core.stop(userInitiated: true)
    }
    try Data().write(to: fixture.directory.appendingPathComponent("validation-released"))
    await launch.value

    #expect(!fixture.core.isProcessRunning)
    #expect(fixture.core.status == .stopped)
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("runtime-started").path))
}

@MainActor
@Test func cancelingAfterCoreLaunchReapsTheStartedProcess() async throws {
    let fixture = try CoreLaunchRaceFixture()
    defer { fixture.cleanup() }
    try Data().write(to: fixture.directory.appendingPathComponent("validation-released"))
    let launch = Task { await fixture.core.start(configPath: fixture.config.path, runtimeDirectoryURL: fixture.directory) }
    try await fixture.waitForFile("runtime-started")
    launch.cancel()
    await launch.value

    #expect(!fixture.core.isProcessRunning)
    #expect(fixture.core.status == .stopped)
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("mihomo.pid").path))
}

@MainActor
private final class CoreLaunchRaceFixture {
    let directory: URL
    let config: URL
    let core: MihomoCoreService

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NexoraLaunchRace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        config = directory.appendingPathComponent("config.yaml")
        try "rules: [MATCH,DIRECT]\n".write(to: config, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        fixture_root="$(dirname "$0")"
        if [ "$1" = "-t" ]; then
          touch "$fixture_root/validation-started"
          attempts=0
          while [ ! -f "$fixture_root/validation-released" ]; do
            attempts=$((attempts + 1))
            if [ "$attempts" -gt 500 ]; then exit 1; fi
            /bin/sleep 0.01
          done
          exit 0
        fi
        trap 'exit 0' TERM
        touch "$fixture_root/runtime-started"
        while :; do /bin/sleep 0.01; done
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        core = MihomoCoreService(coreBinaryURL: executable, privilegedTUN: nil)
    }

    func waitForFile(_ name: String) async throws {
        let url = directory.appendingPathComponent(name)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: url.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(FileManager.default.fileExists(atPath: url.path))
    }

    func cleanup() {
        try? Data().write(to: directory.appendingPathComponent("validation-released"))
        core.stopImmediately()
        try? FileManager.default.removeItem(at: directory)
    }
}
