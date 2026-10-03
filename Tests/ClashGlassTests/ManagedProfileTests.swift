import Foundation
import Testing
@testable import ClashGlassCore

@Test func managedProfileImportSurvivesDeletingTheOriginalFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("source.yaml")
    let managedRoot = directory.appendingPathComponent("Managed", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n"
        .write(to: sourceURL, atomically: true, encoding: .utf8)

    let repository = ManagedProfileRepository(rootURL: managedRoot)
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }
    try FileManager.default.removeItem(at: sourceURL)
    let runtimeURL = try repository.materialize(profile: profile)

    #expect(FileManager.default.fileExists(atPath: profile.managedConfigURL.path))
    #expect(try String(contentsOf: runtimeURL, encoding: .utf8).contains("MATCH,DIRECT"))
}

@Test func managedProfileImportRejectsInvalidConfigurationWithoutPersistingIt() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("broken.yaml")
    let managedRoot = directory.appendingPathComponent("Managed", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "not: valid: yaml".write(to: sourceURL, atomically: true, encoding: .utf8)

    let repository = ManagedProfileRepository(rootURL: managedRoot)

    await #expect(throws: ManagedProfileError.validationFailed("bad config")) {
        _ = try await repository.importProfile(from: sourceURL) { _ in
            .failure("bad config")
        }
    }
    #expect(try repository.loadProfiles().isEmpty)
}

@Test func managedProfileRegistryPersistsSelection() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("profile.yml")
    let managedRoot = directory.appendingPathComponent("Managed", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890".write(to: sourceURL, atomically: true, encoding: .utf8)

    let repository = ManagedProfileRepository(rootURL: managedRoot)
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }
    try repository.select(profile.id)

    let restored = ManagedProfileRepository(rootURL: managedRoot)
    #expect(try restored.loadProfiles().map(\.id) == [profile.id])
    #expect(try restored.selectedProfileID() == profile.id)
}

@MainActor
@Test func failedRegistryImportDoesNotLeaveAnOrphanConfiguration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Managed")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("config.yaml")
    try "mixed-port: 7890".write(to: source, atomically: true, encoding: .utf8)
    try "broken registry".write(to: root.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
    let repository = ManagedProfileRepository(rootURL: root)
    await #expect(throws: DecodingError.self) {
        try await repository.importProfile(from: source) { _ in .success }
    }
    let profiles = root.appendingPathComponent("Profiles")
    #expect((try? FileManager.default.contentsOfDirectory(atPath: profiles.path))?.isEmpty != false)
    #expect(try String(contentsOf: root.appendingPathComponent("profiles.json"), encoding: .utf8) == "broken registry")
}

@MainActor
@Test func failedRegistrySaveDoesNotDeleteAnExistingConfiguration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = directory.appendingPathComponent("Managed")
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("config.yaml")
    try "mixed-port: 7890".write(to: source, atomically: true, encoding: .utf8)
    let repository = ManagedProfileRepository(rootURL: root)
    let profile = try await repository.importProfile(from: source) { _ in .success }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
    #expect(throws: (any Error).self) { try repository.remove(profile.id) }
    #expect(FileManager.default.fileExists(atPath: profile.managedConfigURL.path))
    #expect(try repository.loadProfiles().map(\.id) == [profile.id])
    #expect(try repository.selectedProfileID() == profile.id)
}

@Test func managedProfileRenamePersistsAndTrimsWhitespace() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("profile.yml")
    let managedRoot = directory.appendingPathComponent("Managed", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890".write(to: sourceURL, atomically: true, encoding: .utf8)

    let repository = ManagedProfileRepository(rootURL: managedRoot)
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }

    let renamed = try repository.rename(profile.id, to: "  Work VPN  ")

    #expect(renamed.name == "Work VPN")
    #expect(try ManagedProfileRepository(rootURL: managedRoot).loadProfiles().first?.name == "Work VPN")
}

@Test func managedProfileRenameRejectsAnEmptyName() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = directory.appendingPathComponent("profile.yml")
    let managedRoot = directory.appendingPathComponent("Managed", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "mixed-port: 7890".write(to: sourceURL, atomically: true, encoding: .utf8)

    let repository = ManagedProfileRepository(rootURL: managedRoot)
    let profile = try await repository.importProfile(from: sourceURL) { _ in .success }

    #expect(throws: ManagedProfileError.invalidName) {
        try repository.rename(profile.id, to: "   ")
    }
}

@Test func configurationInspectorExtractsRuntimeSettings() throws {
    let yaml = """
    mixed-port: 7890
    external-controller: '127.0.0.1:9090'
    secret: "glass-secret"
    mode: global
    tun:
      enable: true
    """

    let settings = try MihomoConfigurationInspector.inspect(yaml: yaml)

    #expect(settings.httpPort == 7890)
    #expect(settings.socksPort == 7890)
    #expect(settings.controllerHost == "127.0.0.1")
    #expect(settings.controllerPort == 9090)
    #expect(settings.secret == "glass-secret")
    #expect(settings.mode == .global)
    #expect(settings.tunEnabled == true)
}

@MainActor
@Test func coreValidationRunsTheMihomoTestCommand() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL = directory.appendingPathComponent("fake-mihomo")
    let configURL = directory.appendingPathComponent("config.yaml")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "#!/bin/sh\necho 'configuration rejected' >&2\nexit 1\n"
        .write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    try "broken".write(to: configURL, atomically: true, encoding: .utf8)

    let service = MihomoCoreService(coreBinaryURL: executableURL)
    let validation = await service.validateConfig(path: configURL.path)

    #expect(validation == .failure("configuration rejected"))
}

@Test func coreValidationReportsTheParseErrorInsteadOfTheTemporaryFileSummary() {
    let path = "/private/staging/config.yaml"
    let output = """
    time="2026-10-02T17:00:00+08:00" level=error msg="yaml: unmarshal errors:\\n  line 1: cannot unmarshal a node subscription into config.RawConfig"
    configuration file \(path) test failed
    """
    let message = MihomoCoreService.validationFailureMessage(from: output, configPath: path)
    #expect(message == "yaml: unmarshal errors:\n  line 1: cannot unmarshal a node subscription into config.RawConfig")
    #expect(!message.contains(path))
}
