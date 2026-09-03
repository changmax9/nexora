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

    public var isProcessRunning: Bool {
        process?.isRunning == true
    }

    public init(coreBinaryURL: URL? = MihomoCoreService.defaultCoreBinaryURL()) {
        self.coreBinaryURL = coreBinaryURL
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
        runtimeDirectoryURL: URL? = nil
    ) async {
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

        let validation = await validateConfig(path: configPath)
        guard validation == .success else {
            if case let .failure(message) = validation {
                status = .failed(message)
            }
            return
        }

        status = .starting
        recentOutput = ""
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
                self.captureOutput()
                if self.status != .stopped {
                    self.status = .failed(self.outputSink?.lastMeaningfulLine ?? "Mihomo exited unexpectedly.")
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
        guard process?.isRunning == true else {
            return
        }
        status = .running
    }

    public func stop(userInitiated: Bool) async {
        status = .stopped
        let processID = process?.processIdentifier
        if process?.isRunning == true {
            process?.terminate()
        }
        try? await Task.sleep(for: .milliseconds(40))
        captureOutput()
        removePIDFile(for: processID)
        process = nil
    }

    public func stopImmediately() {
        status = .stopped
        let processID = process?.processIdentifier
        if process?.isRunning == true {
            process?.terminate()
        }
        captureOutput()
        removePIDFile(for: processID)
        process = nil
    }

    public func validateConfig(path: String) async -> ConfigValidationResult {
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
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .split(whereSeparator: \.isNewline)
                    .last
                    .map(String.init) ?? "Mihomo rejected the configuration."
                return process.terminationStatus == 0 ? .success : .failure(message)
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
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

private final class CoreOutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var logHandle: FileHandle?

    init(logURL: URL) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
    }

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
        try? logHandle?.write(contentsOf: newData)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
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
