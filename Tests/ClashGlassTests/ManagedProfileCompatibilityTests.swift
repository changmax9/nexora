import Foundation
import Testing
@testable import ClashGlassCore

@MainActor
@Test func importingAndValidatingLegacyDNSPoliciesKeepsTheOriginalProfileBytes() async throws {
    let fixture = try ManagedProfileCompatibilityFixture(legacyPolicy: true)
    defer { fixture.cleanup() }
    let original = try Data(contentsOf: fixture.sourceURL)

    // The fixture core models the stricter parser in the updated Mihomo core.
    #expect(await fixture.core.validateConfig(path: fixture.sourceURL.path)
        == .failure("fixture: misplaced plus DNS policy"))
    await fixture.store.importManagedProfile(from: fixture.sourceURL)
    let profile = try #require(fixture.store.managedProfiles.first)

    #expect(fixture.store.lastErrorMessage == nil)
    #expect(fixture.store.validationState(for: profile.id).kind == .valid)
    #expect(try Data(contentsOf: fixture.sourceURL) == original)
    #expect(try Data(contentsOf: profile.managedConfigURL) == original)

    await fixture.store.validateManagedProfile(profile.id)
    #expect(fixture.store.validationState(for: profile.id).kind == .valid)
    #expect(fixture.store.lastErrorMessage == nil)
    await fixture.store.validateAllManagedProfiles()
    #expect(fixture.store.validationState(for: profile.id).kind == .valid)
    #expect(fixture.store.lastErrorMessage == nil)
    #expect(try Data(contentsOf: fixture.sourceURL) == original)
    #expect(try Data(contentsOf: profile.managedConfigURL) == original)

    let paths = try fixture.validationPaths()
    #expect(paths.count == 4)
    #expect(paths.first == fixture.sourceURL.path)
    for path in paths.dropFirst() {
        #expect(path != profile.managedConfigURL.path)
        #expect(path.contains("NexoraValidation-"))
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path
        ))
    }
    #expect(try fixture.validationArgumentCounts() == [3, 3, 3, 3])
}

@MainActor
@Test func ordinaryProfilesRetainTheirExistingValidationPathAndArguments() async throws {
    let fixture = try ManagedProfileCompatibilityFixture(legacyPolicy: false)
    defer { fixture.cleanup() }
    let original = try Data(contentsOf: fixture.sourceURL)

    await fixture.store.importManagedProfile(from: fixture.sourceURL)
    let profile = try #require(fixture.store.managedProfiles.first)
    await fixture.store.validateManagedProfile(profile.id)
    await fixture.store.validateAllManagedProfiles()

    let paths = try fixture.validationPaths()
    #expect(paths.count == 3)
    #expect(paths.first?.contains("/.staging/") == true)
    #expect(Array(paths.dropFirst()) == [profile.managedConfigURL.path, profile.managedConfigURL.path])
    #expect(paths.allSatisfy { !$0.contains("NexoraValidation-") })
    #expect(try fixture.validationArgumentCounts() == [3, 3, 3])
    #expect(fixture.store.validationState(for: profile.id).kind == .valid)
    #expect(fixture.store.lastErrorMessage == nil)
    #expect(try Data(contentsOf: profile.managedConfigURL) == original)
}

@MainActor
private final class ManagedProfileCompatibilityFixture {
    let directory: URL
    let sourceURL: URL
    let core: MihomoCoreService
    let store: AppStore
    private let suiteName: String
    private let defaults: UserDefaults

    init(legacyPolicy: Bool) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexoraManagedCompatibility-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sourceURL = directory.appendingPathComponent("source.yaml")
        var yaml = """
        # Preserve original comments and formatting in the saved profile.
        mixed-port: 17890
        external-controller: '127.0.0.1:19090'
        dns:
          enable: true
          nameserver: [1.1.1.1]
          nameserver-policy:
            '+.example.com': [1.1.1.1]
        """
        if legacyPolicy { yaml += "\n    '+.legacy.+': [9.9.9.9]" }
        yaml += "\nrules: ['MATCH,DIRECT']\n"
        try yaml.write(to: sourceURL, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        fixture_root="$(dirname "$0")"
        printf '%s\\n' "$#" >> "$fixture_root/validation-argument-counts"
        config_path=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -t) shift ;;
            -f) config_path="$2"; shift 2 ;;
            *) echo 'fixture: validation arguments changed' >&2; exit 9 ;;
          esac
        done
        printf '%s\\n' "$config_path" >> "$fixture_root/validation-paths"
        if /usr/bin/grep -Fq '+.legacy.+' "$config_path"; then
          echo 'fixture: misplaced plus DNS policy' >&2
          exit 1
        fi
        if ! /usr/bin/grep -Fq '+.example.com' "$config_path"; then
          echo 'fixture: valid DNS policy was removed' >&2
          exit 1
        fi
        exit 0
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        suiteName = "Nexora.ManagedCompatibility.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        core = MihomoCoreService(coreBinaryURL: executable, privilegedTUN: nil)
        store = AppStore(
            coreService: core,
            profileRepository: ManagedProfileRepository(rootURL: directory.appendingPathComponent("Managed")),
            userDefaults: defaults
        )
    }

    func validationPaths() throws -> [String] {
        try String(contentsOf: directory.appendingPathComponent("validation-paths"), encoding: .utf8)
            .split(whereSeparator: \.isNewline).map(String.init)
    }

    func validationArgumentCounts() throws -> [Int] {
        try String(contentsOf: directory.appendingPathComponent("validation-argument-counts"), encoding: .utf8)
            .split(whereSeparator: \.isNewline).compactMap { Int($0) }
    }

    func cleanup() {
        store.shutdownForApplicationTermination()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
