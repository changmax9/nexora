import Darwin
import Foundation
import Testing
@testable import ClashGlassCore

@MainActor
@Test func coreStopWaitsForGracefulProcessExitBeforeRemovingItsPID() async throws {
    let fixture = try CoreProcessFixture(body: """
    trap '/bin/sleep 0.2; printf done > "$fixture_root/graceful-exit"; exit 0' TERM
    printf '%s' "$$" > "$fixture_root/fixture-runtime.pid"
    while :; do /bin/sleep 0.01; done
    """)
    defer { fixture.cleanup() }
    let pid = try await fixture.start()

    await fixture.core.stop(userInitiated: true)

    #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("graceful-exit").path))
    #expect(Darwin.kill(pid, 0) == -1)
    #expect(!fixture.core.isProcessRunning)
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("mihomo.pid").path))
    #expect(fixture.core.status == .stopped)
}

@MainActor
@Test func canceledCoreStopStillForcesAnUnresponsiveProcessToExit() async throws {
    let fixture = try CoreProcessFixture(body: """
    trap 'printf received > "$fixture_root/term-received"' TERM
    printf '%s' "$$" > "$fixture_root/fixture-runtime.pid"
    while :; do /bin/sleep 0.01; done
    """)
    defer { fixture.cleanup() }
    let pid = try await fixture.start()

    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    let stop = Task { await fixture.core.stop(userInitiated: true) }
    stop.cancel()
    await stop.value

    #expect(ContinuousClock.now < deadline)
    #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("term-received").path))
    #expect(Darwin.kill(pid, 0) == -1)
    #expect(!fixture.core.isProcessRunning)
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("mihomo.pid").path))
}

@MainActor
@Test func immediateCoreStopDoesNotLeaveAnUnresponsiveProcessBehind() async throws {
    let fixture = try CoreProcessFixture(body: """
    trap '' TERM
    printf '%s' "$$" > "$fixture_root/fixture-runtime.pid"
    while :; do /bin/sleep 0.01; done
    """)
    defer { fixture.cleanup() }
    let pid = try await fixture.start()

    fixture.core.stopImmediately()

    #expect(Darwin.kill(pid, 0) == -1)
    #expect(!fixture.core.isProcessRunning)
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("mihomo.pid").path))
}

@MainActor
@Test func unexpectedCoreExitPreservesItsActualFailureMessage() async throws {
    let fixture = try CoreProcessFixture(body: """
    printf '%s' "$$" > "$fixture_root/fixture-runtime.pid"
    printf '%s\\n' 'level=error msg="fixture: exact core failure"' >&2
    while [ ! -f "$fixture_root/crash-now" ]; do /bin/sleep 0.01; done
    exit 7
    """)
    defer { fixture.cleanup() }
    var reportedFailure: String?
    fixture.core.onUnexpectedTermination = { reportedFailure = $0 }
    let pid = try await fixture.start()

    let logURL = fixture.directory.appendingPathComponent("mihomo.log")
    let outputDeadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(try String(contentsOf: logURL, encoding: .utf8)).contains("fixture: exact core failure"),
          ContinuousClock.now < outputDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(String(contentsOf: logURL, encoding: .utf8).contains("fixture: exact core failure"))
    try Data().write(to: fixture.directory.appendingPathComponent("crash-now"))
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reportedFailure == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(reportedFailure == "fixture: exact core failure")
    #expect(fixture.core.status == .failed("fixture: exact core failure"))
    #expect(fixture.core.recentOutput.contains("fixture: exact core failure"))
    #expect(Darwin.kill(pid, 0) == -1)
}

@MainActor
private final class CoreProcessFixture {
    let directory: URL
    let core: MihomoCoreService
    private let configuration: URL
    private var launchedProcessID: pid_t?

    init(body: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NexoraCoreRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configuration = directory.appendingPathComponent("config.yaml")
        try "rules: [MATCH,DIRECT]\n".write(to: configuration, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        if [ "$1" = "-t" ]; then exit 0; fi
        fixture_root="$(dirname "$0")"
        \(body)
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        core = MihomoCoreService(coreBinaryURL: executable, privilegedTUN: nil)
    }

    func start() async throws -> pid_t {
        await core.start(configPath: configuration.path, runtimeDirectoryURL: directory)
        let pid = pid_t(try #require(core.processIdentifier))
        launchedProcessID = pid
        let readyFile = directory.appendingPathComponent("fixture-runtime.pid")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: readyFile.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: readyFile.path))
        core.markRunning()
        return pid
    }

    func cleanup() {
        core.stopImmediately()
        // Also reclaim the recorded child if a regression dropped its Process
        // reference before it actually exited.
        if let pid = launchedProcessID, Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while Darwin.kill(pid, 0) == 0, ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
