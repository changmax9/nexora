import Foundation
import Testing
@testable import ClashGlassCore

// Opt in with a local profile when verifying an actual core upgrade. The source
// remains untouched; validation uses a temporary runtime and never starts TUN.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["NEXORA_VERIFY_PROFILE"] != nil))
func localProfileValidatesWithTheUpdatedCoreWithoutChangingItsSource() async throws {
    let environment = ProcessInfo.processInfo.environment
    let profilePath = try #require(environment["NEXORA_VERIFY_PROFILE"])
    let corePath = try #require(environment["NEXORA_VERIFY_CORE"])
    let geoDataPath = try #require(environment["NEXORA_VERIFY_GEODATA"])
    let source = URL(fileURLWithPath: profilePath)
    let original = try Data(contentsOf: source)
    let runtime = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexoraLocalCompatibility-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: runtime) }
    let prepared = try RuntimeConfigurationPreparer(
        geoDataSourceURL: URL(fileURLWithPath: geoDataPath, isDirectory: true)
    ).prepare(sourceURL: source, runtimeDirectoryURL: runtime)
    let result = await MihomoCoreService(
        coreBinaryURL: URL(fileURLWithPath: corePath), privilegedTUN: nil
    ).validateConfig(path: prepared.configURL.path, runtimeDirectoryURL: runtime)

    #expect(result == .success)
    #expect(try Data(contentsOf: source) == original)

    let repository = ManagedProfileRepository(rootURL: runtime.appendingPathComponent("Managed"))
    let suite = "NexoraLocalCompatibility-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppStore(
        coreService: MihomoCoreService(coreBinaryURL: URL(fileURLWithPath: corePath), privilegedTUN: nil),
        profileRepository: repository,
        runtimeConfigurationPreparer: RuntimeConfigurationPreparer(
            geoDataSourceURL: URL(fileURLWithPath: geoDataPath, isDirectory: true)
        ),
        userDefaults: defaults
    )
    await store.importManagedProfile(from: source)
    #expect(store.lastErrorMessage == nil)
    let imported = try #require(store.managedProfiles.first)
    #expect(try Data(contentsOf: imported.managedConfigURL) == original)
    await store.validateAllManagedProfiles()
    #expect(store.lastErrorMessage == nil)
    #expect(!store.isCoreRunning)
}
