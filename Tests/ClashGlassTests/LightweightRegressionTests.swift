import Darwin
import Foundation
import Testing
@testable import ClashGlassCore

@Test func connectionRowsKeepTheirIdentityAcrossCounterRefreshes() throws {
    func response(upload: Int) -> Data {
        Data("""
        {"connections":[
          {"id":"same-connection","metadata":{"host":"example.com","destinationPort":"443"},"upload":\(upload),"download":20,"chains":["DIRECT"]},
          {"id":"another-connection","metadata":{"host":"example.com","destinationPort":"443"},"upload":1,"download":20,"chains":["DIRECT"]}
        ]}
        """.utf8)
    }
    let first = try MihomoAPIDecoder.connections(from: response(upload: 10))
    let refreshed = try MihomoAPIDecoder.connections(from: response(upload: 30))
    #expect(first.map(\.id) == refreshed.map(\.id))
    #expect(first[0].id != first[1].id)
    #expect(first[0].upload != refreshed[0].upload)
}

@Test func coreLogMemoryKeepsABoundedTailAndTheFullFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let logURL = directory.appendingPathComponent("mihomo.log")
    let sink = CoreOutputSink(logURL: logURL)
    let history = Data(String(repeating: "info π: connection opened\n", count: 100_000).utf8)
    let failure = Data("level=error msg=\"latest failure\"\n".utf8)
    sink.append(history)
    sink.append(failure)
    sink.finish()
    #expect(sink.text.utf8.count <= 65_539)
    #expect(sink.text.contains("π"))
    #expect(sink.lastMeaningfulLine == "latest failure")
    #expect(try Data(contentsOf: logURL) == history + failure)
}

@MainActor
@Test func largeValidationOutputDoesNotBlockTheValidator() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-mihomo")
    let config = directory.appendingPathComponent("config.yaml")
    try "rules: [MATCH,DIRECT]\n".write(to: config, atomically: true, encoding: .utf8)
    try """
    #!/bin/sh
    echo $$ > "$(dirname "$0")/validator.pid"
    /usr/bin/head -c 524288 /dev/zero | /usr/bin/tr '\\000' x
    echo
    echo 'level=error msg="large output rejected"'
    exit 1
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let core = MihomoCoreService(coreBinaryURL: executable)
    var finished = false
    let validation = Task {
        let result = await core.validateConfig(path: config.path)
        finished = true
        return result
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !finished, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    let completedWithoutIntervention = finished
    if !finished {
        let pid = try String(contentsOf: directory.appendingPathComponent("validator.pid"), encoding: .utf8)
        _ = Darwin.kill(try #require(Int32(pid.trimmingCharacters(in: .whitespacesAndNewlines))), SIGTERM)
    }
    let result = await validation.value
    #expect(completedWithoutIntervention)
    let preservedFailure = result == .failure("large output rejected")
    #expect(preservedFailure)
}
