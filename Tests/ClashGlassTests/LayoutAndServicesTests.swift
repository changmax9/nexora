import Foundation
import Testing
@testable import ClashGlassCore

@Test func dashboardUsesTheSamePageInsetsAsFeatureScreens() {
    let metrics = DashboardPageMetrics(availableWidth: 854)

    #expect(metrics.horizontalInset == 28)
    #expect(metrics.contentWidth == 798)
}

@Test func dashboardRowUsesOneSharedHeightPartition() {
    let row = DashboardRowMetrics(
        totalHeight: DashboardRowMetrics.standardTotalHeight,
        gap: 16
    )

    #expect(DashboardRowMetrics.standardTotalHeight >= OutboundModeLayoutMetrics.minimumHeight)
    #expect(row.upperHeight == 84)
    #expect(row.lowerHeight == 84)
    #expect(row.upperHeight + row.gap + row.lowerHeight == row.totalHeight)
    #expect(OutboundModeLayoutMetrics.rowSpacing <= 4)
    #expect(
        OutboundModeLayoutMetrics.requiredContentHeight
            <= DashboardRowMetrics.standardTotalHeight
    )
    #expect(OutboundModeLayoutMetrics.cardHeight == DashboardRowMetrics.standardTotalHeight)
}

@Test func dashboardTopRowAlignsNetworkSpeedWithTunBottomEdge() {
    let row = DashboardRowMetrics(
        totalHeight: DashboardRowMetrics.standardTotalHeight,
        gap: 16
    )

    #expect(DashboardTopRowLayoutMetrics.networkSpeedHeight == row.totalHeight)
    #expect(DashboardTopRowLayoutMetrics.toggleCardHeight == row.upperHeight)
    #expect(
        DashboardTopRowLayoutMetrics.toggleCardHeight * 2 + row.gap
            == DashboardTopRowLayoutMetrics.networkSpeedHeight
    )
}

@Test func dashboardLayoutScalesDownInsteadOfOverflowingSmallWindows() {
    let layout = DashboardLayoutMetrics(availableWidth: 760, availableHeight: 520)

    #expect(layout.scale < 1)
    #expect(layout.renderedWidth <= 760)
    #expect(layout.renderedHeight <= 520)
}

@Test func directNetworkIdentityFetcherExplicitlyBypassesProxySettings() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-curl")
    let argumentsURL = directory.appendingPathComponent("arguments.txt")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try """
    #!/bin/sh
    printf '%s\n' "$@" > "\(argumentsURL.path)"
    printf '%s' '{"success":true,"ip":"203.0.113.8","country_code":"US","country":"United States"}'
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let fetcher = DirectNetworkIdentityFetcher(executableURL: executableURL)
    let identity = try await fetcher.fetch(
        endpoint: URL(string: "https://ipwho.is/")!
    )
    let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)

    #expect(identity.ip == "203.0.113.8")
    #expect(identity.countryCode == "US")
    #expect(arguments.contains("--ipv4"))
    #expect(arguments.contains("--noproxy\n*"))
    #expect(arguments.contains("--proxy\n\n"))
}

@Test func systemTunnelRouteDetectorRecognizesBroadUtunRoutes() {
    let routedThroughTunnel = """
    Routing tables

    Internet:
    Destination        Gateway            Flags               Netif Expire
    default            192.168.1.1        UGScg                 en0
    1                  198.18.0.1         UGSc                utun6
    2/7                198.18.0.1         UGSc                utun6
    128.0/1            198.18.0.1         UGSc                utun6
    198.18.0.1         198.18.0.1         UH                  utun6
    """
    let normalWiFiRoute = """
    Routing tables

    Internet:
    Destination        Gateway            Flags               Netif Expire
    default            192.168.1.1        UGScg                 en0
    192.168.1          link#14            UCS                   en0
    """

    #expect(SystemTunnelRouteDetector.isActive(in: routedThroughTunnel))
    #expect(!SystemTunnelRouteDetector.isActive(in: normalWiFiRoute))
}

@Test func networkPortProbeParsesListeningProcessOwners() {
    let output = """
    COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    ClashGlas 97948 max   21u  IPv4 0x123456789      0t0  TCP 127.0.0.1:7890 (LISTEN)
    clash-ver  570 root   11u  IPv4 0x987654321      0t0  TCP 127.0.0.1:9090 (LISTEN)
    """
    let checks = NetworkPortProbe.parse(
        output: output,
        targets: [
            NetworkPortTarget(label: "HTTP Proxy", port: 7890),
            NetworkPortTarget(label: "Socks Proxy", port: 7891),
            NetworkPortTarget(label: "Controller", port: 9090),
        ]
    )

    #expect(checks.first(where: { $0.port == 7890 })?.ownerName == "ClashGlas")
    #expect(checks.first(where: { $0.port == 7890 })?.isListening == true)
    #expect(checks.first(where: { $0.port == 7891 })?.isListening == false)
    #expect(checks.first(where: { $0.port == 9090 })?.ownerPID == 570)
}

@Test func dashboardLayoutUsesFullScaleWhenSpaceAllows() {
    let layout = DashboardLayoutMetrics(availableWidth: 1320, availableHeight: 820)

    #expect(layout.scale == 1)
    #expect(layout.renderedWidth == DashboardLayoutMetrics.baseWidth)
}

@Test func appChromeLayoutScalesTheWholeInterfaceDown() {
    let layout = AppChromeLayoutMetrics(availableWidth: 980, availableHeight: 720)

    #expect(layout.railWidth == 74)
    #expect(layout.topInset == 16)
    #expect(layout.contentWidth == 906)
    #expect(layout.contentLeadingInset == 28)
    #expect(layout.contentTrailingInset == 24)
    #expect(layout.stageWidth == 854)
    #expect(layout.usesWideDashboard == false)
}

@Test func appChromeLayoutUsesWideDashboardOnlyWhenThereIsRoom() {
    let layout = AppChromeLayoutMetrics(availableWidth: 1280, availableHeight: 900)

    #expect(layout.railWidth == 74)
    #expect(layout.contentWidth == 1_206)
    #expect(layout.usesWideDashboard == true)
}

@Test func mainWindowLaunchSizePreventsTheKnownToolbarCollision() {
    #expect(MainWindowLayoutMetrics.minimumWidth == 900)
    #expect(MainWindowLayoutMetrics.minimumHeight == 600)
    #expect(MainWindowLayoutMetrics.defaultWidth >= MainWindowLayoutMetrics.minimumWidth)
    #expect(MainWindowLayoutMetrics.defaultHeight >= MainWindowLayoutMetrics.minimumHeight)
    #expect(MainWindowLayoutMetrics.needsLaunchExpansion(width: 760, height: 647))
    #expect(!MainWindowLayoutMetrics.needsLaunchExpansion(width: 900, height: 620))

    let launchLayout = AppChromeLayoutMetrics(
        availableWidth: MainWindowLayoutMetrics.defaultWidth,
        availableHeight: MainWindowLayoutMetrics.defaultHeight
    )
    let featureToolbarWidth = launchLayout.stageWidth
        - Double(PageSurfaceMetrics.horizontalInset * 2)
    let diagnosticsToolbarWidth = Double(
        FeatureToolbarLayoutMetrics.requiredHorizontalWidth(
            leadingWidth: FeatureToolbarLayoutMetrics.customLeadingWidth,
            actionCount: 2
        )
    )

    #expect(featureToolbarWidth >= diagnosticsToolbarWidth)
}

@Test func denseFeatureControlsKeepResponsiveFallbacks() {
    #expect(
        FeatureToolbarLayoutMetrics.requiredHorizontalWidth(
            leadingWidth: FeatureToolbarLayoutMetrics.customLeadingWidth,
            actionCount: 2
        ) == 662
    )
    #expect(ProfileCardActionLayoutMetrics.usesStackedFallback)
    #expect(ProfileCardActionLayoutMetrics.minimumGap > 0)
}

@Test func systemProxyCommandsMatchMacOSNetworksetupShape() {
    let command = SystemProxyCommand.enable(service: "Wi-Fi", host: "127.0.0.1", httpPort: 7890, socksPort: 7891)

    #expect(command.executable == "/usr/sbin/networksetup")
    #expect(command.steps.map(\.arguments) == [
        ["-setwebproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "7891"],
    ])
}

@Test func systemProxySnapshotParsesAndRestoresExistingProxy() throws {
    let enabledOutput = """
    Enabled: Yes
    Server: 127.0.0.1
    Port: 7890
    Authenticated Proxy Enabled: 0
    """
    let disabledOutput = """
    Enabled: No
    Server: 127.0.0.1
    Port: 7890
    Authenticated Proxy Enabled: 0
    """
    let snapshot = SystemProxySnapshot(
        web: try SystemProxySettings.parse(networksetupOutput: enabledOutput),
        secureWeb: try SystemProxySettings.parse(networksetupOutput: enabledOutput),
        socks: try SystemProxySettings.parse(networksetupOutput: disabledOutput)
    )

    let command = SystemProxyCommand.restore(service: "Wi-Fi", snapshot: snapshot)

    #expect(snapshot.web.enabled)
    #expect(snapshot.web.host == "127.0.0.1")
    #expect(snapshot.web.port == 7890)
    #expect(command.steps.map(\.arguments) == [
        ["-setwebproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setwebproxystate", "Wi-Fi", "on"],
        ["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setsecurewebproxystate", "Wi-Fi", "on"],
        ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "7890"],
        ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
    ])
}

@MainActor
@Test func coreServiceTracksStartStopAndConfigValidation() async throws {
    let service = MihomoCoreService(coreBinaryURL: nil)

    #expect(service.status == .stopped)
    await service.start(configPath: "/tmp/config.yaml")
    #expect(service.status == .missingCoreBinary)

    let validation = await service.validateConfig(path: "")
    #expect(validation == .failure("Config path is empty."))

    await service.stop(userInitiated: true)
    #expect(service.status == .stopped)
}

@MainActor
@Test func coreServiceLaunchesWithRuntimeDirectoryAndReportsExitOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    let configURL = directory.appendingPathComponent("config.yaml")
    let argumentsURL = directory.appendingPathComponent("arguments.txt")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    #!/bin/sh
    if [ "$1" = "-t" ]; then
      exit 0
    fi
    printf '%s\n' "$@" > "\(argumentsURL.path)"
    echo 'runtime bind failed' >&2
    exit 23
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    try "mixed-port: 17890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: configURL, atomically: true, encoding: .utf8)

    let service = MihomoCoreService(coreBinaryURL: executableURL)
    await service.start(configPath: configURL.path, runtimeDirectoryURL: directory)
    try await Task.sleep(for: .milliseconds(100))

    let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
    #expect(arguments.contains("-m"))
    #expect(arguments.contains("-d\n\(directory.path)"))
    #expect(arguments.contains("-f\n\(configURL.path)"))
    #expect(service.recentOutput.contains("runtime bind failed"))
    #expect(service.status == .failed("runtime bind failed"))
}

@MainActor
@Test func coreServiceCanStopImmediatelyDuringApplicationTermination() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    let configURL = directory.appendingPathComponent("config.yaml")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    #!/bin/sh
    if [ "$1" = "-t" ]; then
      exit 0
    fi
    sleep 20
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    try "mixed-port: 17890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: configURL, atomically: true, encoding: .utf8)

    let service = MihomoCoreService(coreBinaryURL: executableURL)
    await service.start(configPath: configURL.path, runtimeDirectoryURL: directory)
    #expect(service.isProcessRunning)
    #expect(
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("mihomo.pid").path
        )
    )

    service.stopImmediately()

    #expect(service.status == .stopped)
    #expect(service.isProcessRunning == false)
    #expect(
        !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("mihomo.pid").path
        )
    )
}

@MainActor
@Test func coreServiceReplacesARecordedOrphanBeforeLaunching() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    let configURL = directory.appendingPathComponent("config.yaml")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try """
    #!/bin/sh
    if [ "$1" = "-t" ]; then
      exit 0
    fi
    sleep 20
    """.write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    try "mixed-port: 17890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: configURL, atomically: true, encoding: .utf8)

    let first = MihomoCoreService(coreBinaryURL: executableURL)
    await first.start(configPath: configURL.path, runtimeDirectoryURL: directory)
    let firstRecord = try String(
        contentsOf: directory.appendingPathComponent("mihomo.pid"),
        encoding: .utf8
    )
    let firstPID = firstRecord.split(whereSeparator: \.isNewline).first

    let replacement = MihomoCoreService(coreBinaryURL: executableURL)
    await replacement.start(configPath: configURL.path, runtimeDirectoryURL: directory)
    try await Task.sleep(for: .milliseconds(120))
    let replacementRecord = try String(
        contentsOf: directory.appendingPathComponent("mihomo.pid"),
        encoding: .utf8
    )
    let replacementPID = replacementRecord.split(whereSeparator: \.isNewline).first

    #expect(firstPID != replacementPID)
    #expect(first.isProcessRunning == false)
    #expect(replacement.isProcessRunning)

    replacement.stopImmediately()
}
