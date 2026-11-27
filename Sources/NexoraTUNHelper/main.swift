import Darwin
import Foundation
import NexoraTUNSupport
import Security

// All process ownership is confined to this queue. There is no arbitrary command,
// executable path, destination path, or PID operation in the XPC interface.
final class Runtime: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.maxchang.Nexora.TUNHelper.runtime")
    private let teamIdentifier: String
    private let executableSnapshot: TUNExecutableSnapshot
    private let bundleContentsURL: URL
    private let launchDate = Date()
    private var activeSessions = Set<UUID>()
    private var idleExitWorkItem: DispatchWorkItem?
    private var owner: UUID?
    private var process: Process?
    private var directory: URL?
    private var pipe: Pipe?
    private var output = Data()

    init(
        teamIdentifier: String,
        executableSnapshot: TUNExecutableSnapshot,
        bundleContentsURL: URL
    ) {
        self.teamIdentifier = teamIdentifier
        self.executableSnapshot = executableSnapshot
        self.bundleContentsURL = bundleContentsURL
    }

    var clientRequirement: String? {
        try? TUNServiceIdentity.requirement(
            identifier: "com.maxchang.Nexora",
            teamIdentifier: teamIdentifier
        )
    }

    func acceptSession(_ id: UUID) -> Bool {
        queue.sync {
            let matchesDisk = executableSnapshot.matchesCurrentOnDisk()
            let active = process?.isRunning == true
            if TUNHelperLifecyclePolicy.shouldRejectAndExitOnIncomingConnection(
                binaryMatchesOnDisk: matchesDisk,
                hasActiveProcess: active
            ) {
                queue.asyncAfter(deadline: .now() + .milliseconds(20)) {
                    exit(0)
                }
                return false
            }
            idleExitWorkItem?.cancel()
            idleExitWorkItem = nil
            activeSessions.insert(id)
            return true
        }
    }

    func endSession(_ id: UUID) {
        queue.async { [self] in
            stop(owner: id)
            activeSessions.remove(id)
            scheduleIdleExitIfNeeded()
        }
    }

    func scheduleIdleExitIfNeeded() {
        guard activeSessions.isEmpty, process?.isRunning != true else { return }
        idleExitWorkItem?.cancel()
        let delay = TUNHelperLifecyclePolicy.idleExitDelay(
            binaryMatchesOnDisk: executableSnapshot.matchesCurrentOnDisk(),
            uptimeSeconds: Date().timeIntervalSince(launchDate)
        )
        let workItem = DispatchWorkItem { [self] in
            guard activeSessions.isEmpty, process?.isRunning != true else { return }
            exit(0)
        }
        idleExitWorkItem = workItem
        queue.asyncAfter(deadline: .now() + max(delay, 0.02), execute: workItem)
    }

    func start(owner: UUID, data: Data) throws {
        guard self.owner == nil || self.owner == owner else {
            throw TUNServiceError("Another Nexora session already owns TUN.")
        }
        stop(owner: owner)
        if !executableSnapshot.matchesCurrentOnDisk() {
            exit(0)
        }
        let normalized = try TUNConfiguration.validateAtBoundary(data)
        let core = bundleContentsURL.appendingPathComponent("Resources/mihomo")
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        let expected = try TUNServiceIdentity.requirement(
            identifier: "com.maxchang.Nexora.mihomo",
            teamIdentifier: teamIdentifier
        )
        guard SecRequirementCreateWithString(expected as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(core as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode, SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw TUNServiceError("The bundled Mihomo signature does not match Nexora.")
        }
        let directory = URL(fileURLWithPath: "/var/run/nexora-tun-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let config = directory.appendingPathComponent("config.yaml")
            try normalized.write(to: config, options: .atomic)
            let geo = bundleContentsURL.appendingPathComponent("Resources/GeoData")
            for name in ["geoip.dat", "geosite.dat", "country.mmdb", "geoip.metadb", "ASN.mmdb"] {
                let source = geo.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: source.path) {
                    try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
                }
            }
            let child = Process()
            let pipe = Pipe()
            child.executableURL = core
            child.arguments = ["-m", "-d", directory.path, "-f", config.path]
            child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": directory.path]
            child.standardOutput = pipe
            child.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.output.append(chunk)
                    if self.output.count > 65_536 { self.output = self.output.suffix(65_536) }
                }
            }
            try child.run()
            self.owner = owner
            self.directory = directory
            self.pipe = pipe
            self.process = child
            self.output = Data()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func stop(owner: UUID? = nil) {
        guard owner == nil || owner == self.owner else { return }
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        process = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        self.owner = nil
    }

    func status(owner: UUID) -> (Bool, String) {
        guard self.owner == owner else { return (false, "TUN session is not running.") }
        return (process?.isRunning == true, String(data: output, encoding: .utf8) ?? "")
    }
}

final class Session: NSObject, TUNHelperProtocol, @unchecked Sendable {
    let id = UUID()
    let runtime: Runtime
    init(runtime: Runtime) { self.runtime = runtime }
    func start(configuration: Data, reply: @escaping @Sendable (String?) -> Void) {
        runtime.queue.sync {
            do { try runtime.start(owner: id, data: configuration); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func stop(reply: @escaping @Sendable () -> Void) { runtime.queue.sync { runtime.stop(owner: id); reply() } }
    func status(reply: @escaping @Sendable (Bool, String) -> Void) {
        runtime.queue.sync { let result = runtime.status(owner: id); reply(result.0, result.1) }
    }
    func invalidate() { runtime.endSession(id) }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let runtime: Runtime
    init(runtime: Runtime) {
        self.runtime = runtime
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0,
              let requirement = runtime.clientRequirement else { return false }
        let session = Session(runtime: runtime)
        guard runtime.acceptSession(session.id) else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: TUNHelperProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.invalidate() }
        connection.interruptionHandler = { session.invalidate() }
        connection.resume()
        return true
    }
}

guard geteuid() == 0 else { exit(77) }
umask(0o077)
guard let teamIdentifier = try? TUNServiceIdentity.teamIdentifier(),
      let executableURL = Bundle.main.executableURL?.resolvingSymlinksInPath(),
      let executableSnapshot = TUNExecutableSnapshot.capture(path: executableURL.path) else {
    exit(78)
}
let bundleContentsURL = executableURL.deletingLastPathComponent().deletingLastPathComponent()
let runtime = Runtime(
    teamIdentifier: teamIdentifier,
    executableSnapshot: executableSnapshot,
    bundleContentsURL: bundleContentsURL
)
let delegate = ListenerDelegate(runtime: runtime)
let listener = NSXPCListener(machServiceName: TUNServiceIdentity.name)
listener.delegate = delegate
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: runtime.queue)
termination.setEventHandler { runtime.stop(); exit(0) }
termination.resume()
listener.resume()
runtime.queue.async { runtime.scheduleIdleExitIfNeeded() }
dispatchMain()
