import Foundation
import Darwin

struct SystemProxyRecoveryState: Codable, Equatable, Sendable {
    let service: String
    let snapshot: SystemProxySnapshot
    let managedProxy: SystemProxySnapshot?
    let ownerPID: Int32?
    let ownerExecutablePath: String?

    init(
        service: String, snapshot: SystemProxySnapshot,
        managedProxy: SystemProxySnapshot? = nil, ownerPID: Int32? = nil,
        ownerExecutablePath: String? = nil
    ) {
        self.service = service
        self.snapshot = snapshot
        self.managedProxy = managedProxy
        self.ownerPID = ownerPID
        self.ownerExecutablePath = ownerExecutablePath
    }

    static func ownedByCurrentProcess(service: String, snapshot: SystemProxySnapshot, managedProxy: SystemProxySnapshot) -> Self {
        let pid = ProcessInfo.processInfo.processIdentifier
        return .init(service: service, snapshot: snapshot, managedProxy: managedProxy,
                     ownerPID: pid, ownerExecutablePath: executablePath(pid: pid))
    }

    var isOwnedByRunningProcess: Bool {
        guard let ownerPID, ownerPID > 0, let ownerExecutablePath else { return false }
        return Self.executablePath(pid: ownerPID) == ownerExecutablePath
    }

    private static func executablePath(pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a C expression macro not imported by Swift.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Write the original settings before changing macOS, so a relaunch never
/// mistakes Nexora's still-enabled proxy for the user's original settings.
struct SystemProxyRecoveryRepository: Sendable {
    let rootURL: URL

    private var fileURL: URL {
        rootURL.appendingPathComponent("system-proxy-recovery.json")
    }

    func load() throws -> SystemProxyRecoveryState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(SystemProxyRecoveryState.self, from: Data(contentsOf: fileURL))
    }

    func save(_ state: SystemProxyRecoveryState) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
