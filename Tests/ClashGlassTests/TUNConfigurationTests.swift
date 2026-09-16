import Foundation
import NexoraTUNSupport
import Testing
@testable import ClashGlassCore

private let tunProfile = """
mixed-port: 17890
external-controller: 127.0.0.1:19090
allow-lan: true
external-controller-unix: /tmp/untrusted.sock
external-ui: /tmp/untrusted-ui
proxies: []
proxy-groups: []
rules: [MATCH,DIRECT]
"""

@Test func tunConfigurationCreatesAuthenticatedLoopbackRuntime() throws {
    let secret = UUID().uuidString + UUID().uuidString
    let yaml = try TUNConfiguration.normalized(yaml: tunProfile, secret: secret)
    let settings = try MihomoConfigurationInspector.inspect(yaml: yaml)
    #expect(settings.secret == secret)
    #expect(settings.tunEnabled)
    #expect(!yaml.contains("untrusted"))
    #expect(yaml.contains("stack: gvisor"))
    #expect(yaml.contains("auto-route: true"))
    #expect(yaml.contains("auto-detect-interface: true"))
    #expect(yaml.contains("allow-lan: false"))
    #expect(yaml.contains("dns-hijack:"))
    #expect(!tunProfile.contains(secret))
    #expect(!(try TUNConfiguration.validateAtBoundary(Data(yaml.utf8))).isEmpty)
}

@Test func tunBoundaryRejectsMissingSecret() {
    #expect(throws: (any Error).self) { try TUNConfiguration.validateAtBoundary(Data(tunProfile.utf8)) }
}

@Test(arguments: ["0.0.0.0:19090", "127.0.0.1:22", "localhost:19090"])
func tunBoundaryRejectsPublicOrPrivilegedController(_ address: String) {
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: tunProfile.replacingOccurrences(of: "127.0.0.1:19090", with: address), secret: UUID().uuidString)
    }
}

@Test(arguments: ["/etc/sudoers", "../../outside", "~/outside", "../outside"])
func tunBoundaryRejectsProviderPathEscape(_ path: String) {
    let profile = tunProfile + "\nproxy-providers:\n  remote:\n    type: http\n    url: https://example.com/proxies.yaml\n    path: '\(path)'\n"
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: profile, secret: UUID().uuidString)
    }
}

@Test func tunBoundaryRejectsExternalFileProviders() {
    let profile = tunProfile + "\nproxy-providers:\n  local:\n    type: file\n    path: local.yaml\n"
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: profile, secret: UUID().uuidString)
    }
}

@Test func tunBoundaryRejectsOversizedConfiguration() {
    #expect(throws: (any Error).self) {
        try TUNConfiguration.validateAtBoundary(Data(repeating: 65, count: TUNConfiguration.maximumSize + 1))
    }
}

@Test func tunBoundaryRejectsPrivilegedCertificateFileReads() {
    let yaml = tunProfile.replacingOccurrences(of: "proxies: []", with: "proxies:\n  - name: tls\n    type: trojan\n    certificate: /var/root/private.pem")
    #expect(throws: (any Error).self) {
        try TUNConfiguration.normalized(yaml: yaml, secret: UUID().uuidString)
    }
}

@MainActor
final class FakePrivilegedTUNRuntime: PrivilegedTUNRuntime {
    var isRunning = false { didSet { onRunningChange?(isRunning) } }
    var onRunningChange: ((Bool) -> Void)?
    var onUnexpectedTermination: ((String) -> Void)?
    var output = ""
    func runtimeOutput() async -> String { output }
    var rejectAuthorization = false
    var rejectStart = false
    var startCount = 0
    var stopCount = 0
    func authorize() throws {
        if rejectAuthorization { throw TUNServiceError("fixture: approval required") }
    }
    func start(configuration: Data) async throws {
        startCount += 1
        if rejectStart { throw TUNServiceError("fixture: privileged launch rejected") }
        isRunning = true
    }
    func stop() async { stopCount += 1; isRunning = false }
    func invalidate() { isRunning = false }
}

@MainActor
@Test func tunStartupReportsRouteConflictWithoutMislabelingOtherErrors() async {
    let runtime = FakePrivilegedTUNRuntime()
    runtime.isRunning = true
    let core = MihomoCoreService(coreBinaryURL: nil, privilegedTUN: runtime)
    runtime.output = "Start TUN listening error: configure tun interface: add route: 1.0.0.0/8: file exists"
    #expect(await core.tunStartupFailure() == "Another VPN or TUN connection already owns the required routes. Turn off its TUN mode before enabling Nexora TUN.")
    runtime.output = "Start TUN listening error: permission denied"
    #expect(await core.tunStartupFailure() == runtime.output)
    runtime.output = "info: controller ready"
    #expect(await core.tunStartupFailure() == nil)
}

@MainActor
@Test func disconnectedXPCServiceDoesNotCrashOnBackgroundErrorCallback() async {
    let connection = NSXPCConnection(machServiceName: "com.maxchang.Nexora.Tests.Missing.\(UUID().uuidString)")
    connection.remoteObjectInterface = NSXPCInterface(with: TUNHelperProtocol.self)
    connection.resume()
    let service = PrivilegedTUNService(connection: connection)
    #expect(await service.runtimeOutput().isEmpty)
    service.invalidate()
    #expect(!service.isRunning)
}
