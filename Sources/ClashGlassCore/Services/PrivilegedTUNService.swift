import Foundation
import NexoraTUNSupport
import ServiceManagement

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
    public private(set) var isRunning = false
    public private(set) var recentOutput = ""
    public var onUnexpectedTermination: ((String) -> Void)?
    private var connection: NSXPCConnection?
    private var monitor: Task<Void, Never>?

    public init() {}

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    public func authorize() throws {
        _ = try TUNServiceIdentity.requirement(identifier: TUNServiceIdentity.name)
        let service = SMAppService.daemon(plistName: TUNServiceIdentity.plistName)
        // A newly embedded daemon can report notFound before its first registration.
        if service.status == .notRegistered || service.status == .notFound {
            do {
                try service.register()
            } catch {
                // Registration may succeed while bootstrap awaits administrator approval.
                guard service.status == .requiresApproval else { throw error }
            }
        }
        switch service.status {
        case .enabled: return
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            throw TUNServiceError("Allow Nexora in System Settings → General → Login Items & Extensions, then turn TUN on again. Your current connection has been kept running.")
        default:
            throw TUNServiceError("The Nexora TUN helper is unavailable. Reinstall the signed application in Applications and try again.")
        }
    }

    public func start(configuration: Data) async throws {
        try authorize()
        let connection = NSXPCConnection(machServiceName: TUNServiceIdentity.name, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: TUNHelperProtocol.self)
        connection.setCodeSigningRequirement(try TUNServiceIdentity.requirement(identifier: TUNServiceIdentity.name))
        connection.resume()
        self.connection = connection
        do {
            let _: Bool = try await request { proxy, finish in
                proxy.start(configuration: configuration) { message in
                    if let message { finish(.failure(TUNServiceError(message))) }
                    else { finish(.success(true)) }
                }
            }
            isRunning = true
            recentOutput = ""
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                    guard let self, self.isRunning else { return }
                    do {
                        let result: TUNHealth = try await self.request { proxy, finish in
                            proxy.status { running, output in finish(.success(TUNHealth(running: running, output: output))) }
                        }
                        guard !Task.isCancelled else { return }
                        self.recentOutput = result.output
                        if !result.running {
                            self.isRunning = false
                            self.onUnexpectedTermination?(result.output.split(separator: "\n").last.map(String.init) ?? "The TUN runtime exited.")
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
        } catch { invalidate(); throw error }
    }

    public func runtimeOutput() async -> String {
        guard connection != nil else { return recentOutput }
        if let result: TUNHealth = try? await request({ proxy, finish in
            proxy.status { running, output in
                finish(.success(TUNHealth(running: running, output: output)))
            }
        }) { recentOutput = result.output }
        return recentOutput
    }

    public func stop() async {
        monitor?.cancel()
        if connection != nil {
            let _: Bool? = try? await request { proxy, finish in proxy.stop { finish(.success(true)) } }
        }
        invalidate()
    }

    public func invalidate() {
        monitor?.cancel()
        monitor = nil
        isRunning = false
        connection?.invalidate()
        connection = nil
    }

    private func request<Value: Sendable>(
        _ send: (TUNHelperProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        guard let connection else { throw TUNServiceError("The TUN helper is disconnected.") }
        return try await withCheckedThrowingContinuation { continuation in
            let reply = TUNReply(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable error in reply.finish(.failure(error)) }) as? TUNHelperProtocol else {
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

private struct TUNHealth: Sendable { let running: Bool; let output: String }

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
