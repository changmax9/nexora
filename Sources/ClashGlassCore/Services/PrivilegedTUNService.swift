import Foundation
import NexoraTUNSupport
import ServiceManagement

enum TUNDaemonStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol TUNDaemonManaging: Sendable {
    func status() -> TUNDaemonStatus
    func register() throws
    func unregister() async throws
    @MainActor func openApprovalSettings()
}

struct SystemTUNDaemonManager: TUNDaemonManaging {
    private func daemonService() -> SMAppService {
        SMAppService.daemon(plistName: TUNServiceIdentity.plistName)
    }

    func status() -> TUNDaemonStatus {
        switch daemonService().status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws {
        try daemonService().register()
    }

    func unregister() async throws {
        try await daemonService().unregister()
    }

    @MainActor func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct TUNHealth: Sendable {
    let running: Bool
    let output: String
}

protocol TUNHelperSession: AnyObject, Sendable {
    func start(configuration: Data) async throws
    func stop() async
    func status() async throws -> TUNHealth
    func invalidate()
}

final class XPCTUNHelperSession: TUNHelperSession, @unchecked Sendable {
    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func start(configuration: Data) async throws {
        let _: Bool = try await request { proxy, finish in
            proxy.start(configuration: configuration) { message in
                if let message { finish(.failure(TUNServiceError(message))) }
                else { finish(.success(true)) }
            }
        }
    }

    func stop() async {
        let _: Bool? = try? await request { proxy, finish in
            proxy.stop { finish(.success(true)) }
        }
    }

    func status() async throws -> TUNHealth {
        try await request { proxy, finish in
            proxy.status { running, output in
                finish(.success(TUNHealth(running: running, output: output)))
            }
        }
    }

    func invalidate() {
        connection.invalidate()
    }

    private func request<Value: Sendable>(
        _ send: (TUNHelperProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let reply = TUNReply(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable error in
                reply.finish(.failure(error))
            }) as? TUNHelperProtocol else {
                reply.finish(.failure(TUNServiceError("Could not contact the TUN helper.")))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                reply.finish(.failure(TUNServiceError("The TUN helper did not respond in time.")))
            }
            send(proxy) { reply.finish($0) }
        }
    }
}

@MainActor
public protocol PrivilegedTUNRuntime: AnyObject {
    var isRunning: Bool { get }
    var onUnexpectedTermination: ((String) -> Void)? { get set }
    func authorize() throws
    func start(configuration: Data) async throws
    func stop() async
    func invalidate()
    func runtimeOutput() async -> String
}

public extension PrivilegedTUNRuntime {
    func runtimeOutput() async -> String { "" }
}

@MainActor
public final class PrivilegedTUNService: PrivilegedTUNRuntime {
    static let staleHelperRecoveryMessage =
        "Could not connect to the Nexora TUN helper after an app update. Toggle Nexora off and on in System Settings → General → Login Items & Extensions (or restart your Mac), then turn TUN on again."
    private static let approvalRequiredMessage =
        "Allow Nexora in System Settings → General → Login Items & Extensions, then turn TUN on again. Your current connection has been kept running."

    public private(set) var isRunning = false
    public private(set) var recentOutput = ""
    public var onUnexpectedTermination: ((String) -> Void)?

    private let daemon: any TUNDaemonManaging
    private let requirementProvider: @Sendable () throws -> String
    private let sessionFactory: @MainActor @Sendable (String) -> any TUNHelperSession
    private let retryDelay: Duration
    private let reregisterDelay: Duration
    private var session: (any TUNHelperSession)?
    private var monitor: Task<Void, Never>?

    public convenience init() {
        self.init(
            daemon: SystemTUNDaemonManager(),
            requirementProvider: { try TUNServiceIdentity.requirement(identifier: TUNServiceIdentity.name) },
            sessionFactory: nil
        )
    }

    convenience init(connection: NSXPCConnection) {
        self.init()
        session = XPCTUNHelperSession(connection: connection)
    }

    init(
        daemon: any TUNDaemonManaging = SystemTUNDaemonManager(),
        requirementProvider: @escaping @Sendable () throws -> String = {
            try TUNServiceIdentity.requirement(identifier: TUNServiceIdentity.name)
        },
        sessionFactory: (@MainActor @Sendable (String) -> any TUNHelperSession)? = nil,
        retryDelay: Duration = .milliseconds(350),
        reregisterDelay: Duration = .milliseconds(400)
    ) {
        self.daemon = daemon
        self.requirementProvider = requirementProvider
        self.sessionFactory = sessionFactory ?? { requirement in
            let connection = NSXPCConnection(machServiceName: TUNServiceIdentity.name, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: TUNHelperProtocol.self)
            connection.setCodeSigningRequirement(requirement)
            connection.resume()
            return XPCTUNHelperSession(connection: connection)
        }
        self.retryDelay = retryDelay
        self.reregisterDelay = reregisterDelay
    }

    static func isXPCCommunicationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && (
            nsError.code == NSXPCConnectionInterrupted ||
            nsError.code == NSXPCConnectionInvalid
        )
    }

    public func authorize() throws {
        _ = try requirementProvider()
        let initialStatus = daemon.status()
        // A newly embedded daemon can report notFound before its first registration.
        if initialStatus == .notRegistered || initialStatus == .notFound {
            do {
                try daemon.register()
            } catch {
                // Registration may succeed while bootstrap awaits administrator approval.
                guard daemon.status() == .requiresApproval else { throw error }
            }
        }
        switch daemon.status() {
        case .enabled:
            return
        case .requiresApproval:
            daemon.openApprovalSettings()
            throw TUNServiceError(Self.approvalRequiredMessage)
        default:
            throw TUNServiceError("The Nexora TUN helper is unavailable. Reinstall the signed application in Applications and try again.")
        }
    }

    public func start(configuration: Data) async throws {
        try authorize()

        // Stage 1: attempt normal connection. A stale helper exits on contact.
        do {
            try await connectAndStart(configuration: configuration)
            startMonitor()
            return
        } catch {
            guard Self.isXPCCommunicationError(error) else {
                invalidate()
                throw error
            }
        }

        // Stage 2: retry once so launchd can spawn the replacement helper binary.
        invalidate()
        try await Task.sleep(for: retryDelay)
        do {
            try await connectAndStart(configuration: configuration)
            startMonitor()
            return
        } catch {
            guard Self.isXPCCommunicationError(error) else {
                invalidate()
                throw error
            }
        }

        // Stage 3: follow Apple's SMAppService upgrade guidance (unregister -> register)
        // when an older helper process stays stuck rejecting XPC connections.
        invalidate()
        try await refreshDaemonRegistration()
        do {
            try await connectAndStart(configuration: configuration)
            startMonitor()
        } catch {
            invalidate()
            if Self.isXPCCommunicationError(error) {
                throw TUNServiceError(Self.staleHelperRecoveryMessage)
            }
            throw error
        }
    }

    public func runtimeOutput() async -> String {
        guard let session else { return recentOutput }
        if let result = try? await session.status() {
            recentOutput = result.output
        }
        return recentOutput
    }

    public func stop() async {
        monitor?.cancel()
        if let session {
            await session.stop()
        }
        invalidate()
    }

    public func invalidate() {
        monitor?.cancel()
        monitor = nil
        isRunning = false
        session?.invalidate()
        session = nil
    }

    private func connectAndStart(configuration: Data) async throws {
        let requirement = try requirementProvider()
        let createdSession = sessionFactory(requirement)
        session = createdSession
        do {
            try await createdSession.start(configuration: configuration)
        } catch {
            session = nil
            createdSession.invalidate()
            throw error
        }
    }

    private func refreshDaemonRegistration() async throws {
        try? await daemon.unregister()
        try await Task.sleep(for: reregisterDelay)
        do {
            try daemon.register()
        } catch {
            let status = daemon.status()
            guard status == .enabled || status == .requiresApproval else {
                throw TUNServiceError(Self.staleHelperRecoveryMessage)
            }
        }
        switch daemon.status() {
        case .enabled:
            return
        case .requiresApproval:
            daemon.openApprovalSettings()
            throw TUNServiceError(Self.approvalRequiredMessage)
        default:
            throw TUNServiceError(Self.staleHelperRecoveryMessage)
        }
    }

    private func startMonitor() {
        isRunning = true
        recentOutput = ""
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                guard let self, self.isRunning, let session = self.session else { return }
                do {
                    let result = try await session.status()
                    guard !Task.isCancelled else { return }
                    self.recentOutput = result.output
                    if !result.running {
                        self.isRunning = false
                        self.onUnexpectedTermination?(
                            result.output.split(separator: "\n").last.map(String.init) ?? "The TUN runtime exited."
                        )
                        self.invalidate()
                        return
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.isRunning = false
                    self.onUnexpectedTermination?(error.localizedDescription)
                    self.invalidate()
                    return
                }
            }
        }
    }
}

private final class TUNReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
