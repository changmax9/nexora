import Darwin
import Foundation

public enum CoreRuntimeStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case missingCoreBinary
    case failed(String)

    public var failureMessage: String? {
        switch self {
        case .missingCoreBinary:
            "Mihomo core is missing."
        case let .failed(message):
            message
        default:
            nil
        }
    }
}

public enum ConfigValidationResult: Equatable, Sendable {
    case success
    case failure(String)
}

@MainActor
public final class MihomoCoreService {
    public private(set) var status: CoreRuntimeStatus = .stopped
    public private(set) var recentOutput = ""
    public let coreBinaryURL: URL?
    private var process: Process?
    private var outputPipe: Pipe?
    private var outputSink: CoreOutputSink?
    private var pidFileURL: URL?
    private var lifecycleGeneration: UInt64 = 0
    private let privilegedTUN: (any PrivilegedTUNRuntime)?
    var onUnexpectedTermination: (@MainActor (String) -> Void)?

    public var isProcessRunning: Bool {
        process?.isRunning == true || privilegedTUN?.isRunning == true
    }

    var processIdentifier: Int? {
        guard let process, process.isRunning else { return nil }
        return Int(process.processIdentifier)
    }

    public var supportsPrivilegedTUN: Bool { privilegedTUN != nil }
    public var isPrivilegedRunning: Bool { privilegedTUN?.isRunning == true }
    public func authorizeTUN() throws { try privilegedTUN?.authorize() }
    public func tunStartupFailure() async -> String? {
        guard let privilegedTUN, privilegedTUN.isRunning else { return nil }
        let output = await privilegedTUN.runtimeOutput()
        recentOutput = output
        guard let failure = output.split(whereSeparator: \.isNewline).last(where: {
            $0.contains("Start TUN listening error")
        }) else { return nil }
        if failure.contains("add route"), failure.contains("file exists") {
            return "Another VPN or TUN connection already owns the required routes. Turn off its TUN mode before enabling Nexora TUN."
        }
        return String(failure)
    }

    public init(coreBinaryURL: URL? = MihomoCoreService.defaultCoreBinaryURL(), privilegedTUN: (any PrivilegedTUNRuntime)? = PrivilegedTUNService()) {
        self.coreBinaryURL = coreBinaryURL
        self.privilegedTUN = privilegedTUN
        privilegedTUN?.onUnexpectedTermination = { [weak self] message in
            guard let self, self.status != .stopped else { return }
            self.recentOutput = message
            self.status = .failed(message)
            self.onUnexpectedTermination?(message)
        }
    }

    public nonisolated static func defaultCoreBinaryURL() -> URL? {
        candidateCoreBinaryURL(paths: defaultCoreBinaryPaths())
    }

    nonisolated static func defaultCoreBinaryPaths() -> [String] {
        var candidates: [String] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("mihomo").path)
            candidates.append(resourceURL.appendingPathComponent("clash").path)
        }

        if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportURL = supportURL.appendingPathComponent("Nexora", isDirectory: true)
            candidates.append(appSupportURL.appendingPathComponent("mihomo").path)
            candidates.append(appSupportURL.appendingPathComponent("clash").path)
        }

        candidates.append(contentsOf: [
            "\(NSHomeDirectory())/.local/bin/mihomo",
            "\(NSHomeDirectory())/.local/bin/clash",
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo",
            "/opt/homebrew/bin/clash-meta",
            "/usr/local/bin/clash-meta",
            "/opt/homebrew/bin/clash",
            "/usr/local/bin/clash",
        ])
        return candidates
    }

    nonisolated static func candidateCoreBinaryURL(paths: [String]) -> URL? {
        return paths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func start(
        configPath: String,
        runtimeDirectoryURL: URL? = nil,
        useTUN: Bool = false
    ) async {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        guard !Task.isCancelled else { return }
        guard let coreBinaryURL else {
            status = .missingCoreBinary
            return
        }

        do {
            try ensureLaunchConfig(path: configPath)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        let validation = await validateConfig(path: configPath, runtimeDirectoryURL: runtimeDirectoryURL)
        // Validation runs outside the main actor. A stop or newer start may
        // have superseded this launch while the validator was running.
        guard generation == lifecycleGeneration else { return }
        guard !Task.isCancelled else {
            status = .stopped
            return
        }
        guard validation == .success else {
            if case let .failure(message) = validation {
                status = .failed(message)
            }
            return
        }

        status = .starting
        recentOutput = ""
        if useTUN, let privilegedTUN {
            do { try await privilegedTUN.start(configuration: Data(contentsOf: URL(fileURLWithPath: configPath))) }
            catch {
                guard generation == lifecycleGeneration else { return }
                status = .failed(error.localizedDescription)
            }
            if generation == lifecycleGeneration, Task.isCancelled {
                await stop(userInitiated: false)
            }
            return
        }
        let runtimeDirectoryURL = runtimeDirectoryURL
            ?? URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: true
        )
        let pidFileURL = runtimeDirectoryURL.appendingPathComponent("mihomo.pid")
        terminateRecordedProcess(
            at: pidFileURL,
            coreBinaryURL: coreBinaryURL,
            runtimeDirectoryURL: runtimeDirectoryURL
        )
        self.pidFileURL = pidFileURL
        let process = Process()
        let pipe = Pipe()
        let sink = CoreOutputSink(
            logURL: runtimeDirectoryURL.appendingPathComponent("mihomo.log")
        )
        process.executableURL = coreBinaryURL
        process.arguments = [
            "-m",
            "-d", runtimeDirectoryURL.path,
            "-f", configPath,
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            sink.append(data)
        }
        process.terminationHandler = { [weak self, weak process] _ in
            Task { @MainActor in
                guard let self, self.process === process else {
                    return
                }
                let message = self.outputSink?.lastMeaningfulLine ?? "Mihomo exited unexpectedly."
                self.captureOutput()
                if self.status != .stopped {
                    self.status = .failed(message)
                    self.onUnexpectedTermination?(message)
                }
                self.removePIDFile(for: process?.processIdentifier)
                self.process = nil
            }
        }
        do {
            try process.run()
            self.process = process
            outputPipe = pipe
            outputSink = sink
            writePIDFile(
                processID: process.processIdentifier,
                coreBinaryURL: coreBinaryURL,
                to: pidFileURL
            )
            try? await Task.sleep(for: .milliseconds(80))
            guard generation == lifecycleGeneration, self.process === process else { return }
            if Task.isCancelled {
                await stop(userInitiated: false)
                return
            }
            if !process.isRunning {
                captureOutput()
                status = .failed(sink.lastMeaningfulLine ?? "Mihomo exited before its controller became available.")
                removePIDFile(for: process.processIdentifier)
                self.process = nil
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            removePIDFile(for: process.processIdentifier)
            status = .failed(error.localizedDescription)
        }
    }

    public func markRunning() {
        guard isProcessRunning else {
            return
        }
        status = .running
    }

    public func stop(userInitiated: Bool) async {
        lifecycleGeneration &+= 1
        status = .stopped
        let stoppingProcess = process
        await privilegedTUN?.stop()
        if let stoppingProcess {
            // Cleanup must finish even when the caller cancels the transition.
            // Wait off the main actor so controller/UI work remains responsive.
            await Task.detached(priority: .userInitiated) {
                Self.terminateAndWait(stoppingProcess, gracePeriod: .seconds(2))
            }.value
        }
        guard process === stoppingProcess else { return }
        captureOutput()
        removePIDFile(for: stoppingProcess?.processIdentifier)
        process = nil
    }

    public func stopImmediately() {
        lifecycleGeneration &+= 1
        status = .stopped
        privilegedTUN?.invalidate()
        let stoppingProcess = process
        if let stoppingProcess {
            // Application termination cannot await an actor task. Allow a brief
            // graceful exit, then reap the owned child before dropping its PID.
            Self.terminateAndWait(stoppingProcess, gracePeriod: .milliseconds(250))
        }
        captureOutput()
        removePIDFile(for: stoppingProcess?.processIdentifier)
        process = nil
    }

    private nonisolated static func terminateAndWait(_ process: Process, gracePeriod: Duration) {
        if process.isRunning {
            process.terminate()
            let deadline = ContinuousClock.now.advanced(by: gracePeriod)
            while process.isRunning, ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
    }

    public func validateConfig(path: String, runtimeDirectoryURL: URL? = nil) async -> ConfigValidationResult {
        if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure("Config path is empty.")
        }
        if !FileManager.default.fileExists(atPath: path) {
            return .failure("Config file does not exist.")
        }
        guard let coreBinaryURL else {
            return .failure("Mihomo core is missing.")
        }

        return await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = coreBinaryURL
            process.arguments = ["-t", "-f", path]
            if let runtimeDirectoryURL {
                process.arguments = ["-t", "-d", runtimeDirectoryURL.path, "-f", path]
            }
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                // Drain while the child runs: a full pipe otherwise prevents it exiting.
                var tail = CoreOutputTail()
                while let chunk = try output.fileHandleForReading.read(upToCount: 16_384), !chunk.isEmpty {
                    tail.append(chunk)
                }
                process.waitUntilExit()
                return process.terminationStatus == 0 ? .success : .failure(
                    Self.validationFailureMessage(from: tail.text, configPath: path)
                )
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    nonisolated static func validationFailureMessage(from output: String, configPath: String) -> String {
        let lines = output
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let detail = lines.last { $0.contains("level=error") || $0.contains("Parse config error:") }
            ?? lines.last { !($0.hasPrefix("configuration file ") && $0.hasSuffix(" test failed")) }
        guard var message = detail else { return "Mihomo rejected the configuration." }
        if let range = message.range(of: "msg=") {
            let encodedMessage = String(message[range.upperBound...])
            message = (try? JSONDecoder().decode(String.self, from: Data(encodedMessage.utf8)))
                ?? encodedMessage
        }
        return message.replacingOccurrences(of: configPath, with: "configuration")
    }

    public nonisolated func ensureLaunchConfig(path: String) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return
        }
        guard !FileManager.default.fileExists(atPath: trimmedPath) else {
            return
        }

        let url = URL(fileURLWithPath: trimmedPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.defaultLaunchConfig.write(to: url, atomically: true, encoding: .utf8)
    }

    public nonisolated static var defaultLaunchConfig: String {
        """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: info
        external-controller: 127.0.0.1:9090
        proxies: []
        proxy-groups:
          - name: GLOBAL
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
    }

    private func captureOutput() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputSink?.finish()
        recentOutput = outputSink?.text ?? recentOutput
        outputPipe = nil
        outputSink = nil
    }

    private func writePIDFile(
        processID: Int32,
        coreBinaryURL: URL,
        to url: URL
    ) {
        let record = "\(processID)\n\(coreBinaryURL.path)\n"
        try? record.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removePIDFile(for processID: Int32?) {
        guard let pidFileURL,
              let processID,
              let record = try? String(contentsOf: pidFileURL, encoding: .utf8),
              record.split(whereSeparator: \.isNewline).first == Substring("\(processID)") else {
            return
        }
        try? FileManager.default.removeItem(at: pidFileURL)
    }

    private func terminateRecordedProcess(
        at pidFileURL: URL,
        coreBinaryURL: URL,
        runtimeDirectoryURL: URL
    ) {
        defer {
            try? FileManager.default.removeItem(at: pidFileURL)
        }
        guard let record = try? String(contentsOf: pidFileURL, encoding: .utf8) else {
            return
        }
        let lines = record.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2,
              let processID = Int32(lines[0]),
              lines[1] == coreBinaryURL.path,
              processID != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        let inspector = Process()
        let output = Pipe()
        inspector.executableURL = URL(fileURLWithPath: "/bin/ps")
        inspector.arguments = ["-p", "\(processID)", "-o", "command="]
        inspector.standardOutput = output
        inspector.standardError = output
        guard (try? inspector.run()) != nil else {
            return
        }
        inspector.waitUntilExit()
        let command = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard command.contains(coreBinaryURL.path),
              command.contains(runtimeDirectoryURL.path) else {
            return
        }
        Darwin.kill(processID, SIGTERM)
    }
}

private struct CoreOutputTail {
    private static let capacity = 65_536
    private var data = Data()

    mutating func append(_ chunk: Data) {
        if chunk.count >= Self.capacity {
            data = chunk.subdata(in: (chunk.endIndex - Self.capacity)..<chunk.endIndex)
        } else {
            data.append(chunk)
            if data.count > Self.capacity {
                data = data.subdata(in: (data.endIndex - Self.capacity)..<data.endIndex)
            }
        }
    }

    // Trimming can split the first UTF-8 character; preserve the remaining log.
    var text: String { String(decoding: data, as: UTF8.self) }
}

final class CoreOutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = CoreOutputTail()
    private var logHandle: FileHandle?
    private let logURL: URL
    private let previousLogURL: URL
    private let maximumFileBytes: Int
    private var fileBytes = 0

    init(logURL: URL, maximumFileBytes: Int = 4 * 1_024 * 1_024) {
        self.logURL = logURL
        previousLogURL = logURL.appendingPathExtension("previous")
        self.maximumFileBytes = max(1, maximumFileBytes)
        // Preserve the bounded end of the previous run, including an older
        // unbounded log, without reading the entire file into memory.
        if let previousRun = try? FileHandle(forReadingFrom: logURL) {
            defer { try? previousRun.close() }
            if let size = try? previousRun.seekToEnd(), size > 0 {
                let start = size > UInt64(self.maximumFileBytes)
                    ? size - UInt64(self.maximumFileBytes) : 0
                try? previousRun.seek(toOffset: start)
                if let data = try? previousRun.read(upToCount: self.maximumFileBytes) {
                    try? data.write(to: previousLogURL, options: .atomic)
                }
            }
        }
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
    }

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        tail.append(newData)
        var offset = newData.startIndex
        while offset < newData.endIndex, logHandle != nil {
            if fileBytes == maximumFileBytes {
                rotateLog()
            }
            let end = min(newData.endIndex, offset + maximumFileBytes - fileBytes)
            do {
                try logHandle?.write(contentsOf: newData[offset..<end])
                fileBytes += end - offset
                offset = end
            } catch {
                try? logHandle?.close()
                logHandle = nil
            }
        }
    }

    private func rotateLog() {
        try? logHandle?.close()
        logHandle = nil
        do {
            if FileManager.default.fileExists(atPath: previousLogURL.path) {
                try FileManager.default.removeItem(at: previousLogURL)
            }
            try FileManager.default.moveItem(at: logURL, to: previousLogURL)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: logURL)
            fileBytes = 0
        } catch {
            // The in-memory tail remains available if disk logging fails.
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return tail.text
    }

    var lastMeaningfulLine: String? {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(Self.cleanLogLine)
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        try? logHandle?.close()
        logHandle = nil
    }

    private static func cleanLogLine(_ line: String) -> String {
        guard let messageRange = line.range(of: "msg=\""),
              line.hasSuffix("\"") else {
            return line
        }
        return String(line[messageRange.upperBound..<line.index(before: line.endIndex)])
    }
}
