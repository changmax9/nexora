import Foundation

public struct ManagedProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let managedConfigURL: URL
    public let importedAt: Date

    public init(id: UUID, name: String, managedConfigURL: URL, importedAt: Date) {
        self.id = id
        self.name = name
        self.managedConfigURL = managedConfigURL
        self.importedAt = importedAt
    }
}

public enum ManagedProfileError: Error, Equatable, LocalizedError {
    case unsupportedFile
    case validationFailed(String)
    case profileNotFound
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Choose a .yaml or .yml Mihomo configuration."
        case let .validationFailed(message):
            message
        case .profileNotFound:
            "The selected managed profile no longer exists."
        case .invalidName:
            "Profile names cannot be empty."
        }
    }
}

public struct ManagedProfileRepository: Sendable {
    public let rootURL: URL

    private var profilesDirectory: URL {
        rootURL.appendingPathComponent("Profiles", isDirectory: true)
    }

    private var registryURL: URL {
        rootURL.appendingPathComponent("profiles.json")
    }

    public var runtimeConfigURL: URL {
        runtimeDirectoryURL.appendingPathComponent("config.yaml")
    }

    public var runtimeDirectoryURL: URL {
        rootURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    public init(rootURL: URL = Self.defaultRootURL()) {
        self.rootURL = rootURL
    }

    public static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nexora", isDirectory: true)
    }

    @MainActor
    public func importProfile(
        from sourceURL: URL,
        name: String? = nil,
        validate: (URL) async -> ConfigValidationResult
    ) async throws -> ManagedProfile {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard fileExtension == "yaml" || fileExtension == "yml" else {
            throw ManagedProfileError.unsupportedFile
        }

        let id = UUID()
        let stagingDirectory = rootURL
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        let stagedURL = stagingDirectory.appendingPathComponent("config.yaml")
        let destinationDirectory = profilesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let destinationURL = destinationDirectory.appendingPathComponent("config.yaml")

        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
            switch await validate(stagedURL) {
            case .success:
                break
            case let .failure(message):
                throw ManagedProfileError.validationFailed(message)
            }

            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: stagingDirectory, to: destinationDirectory)

            let profile = ManagedProfile(
                id: id,
                name: name ?? sourceURL.deletingPathExtension().lastPathComponent,
                managedConfigURL: destinationURL,
                importedAt: Date()
            )
            var registry = try loadRegistry()
            registry.profiles.append(profile)
            if registry.selectedProfileID == nil {
                registry.selectedProfileID = profile.id
            }
            try saveRegistry(registry)
            return profile
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            throw error
        }
    }

    public func loadProfiles() throws -> [ManagedProfile] {
        try loadRegistry().profiles
    }

    public func selectedProfileID() throws -> ManagedProfile.ID? {
        try loadRegistry().selectedProfileID
    }

    public func select(_ id: ManagedProfile.ID) throws {
        var registry = try loadRegistry()
        guard registry.profiles.contains(where: { $0.id == id }) else {
            throw ManagedProfileError.profileNotFound
        }
        registry.selectedProfileID = id
        try saveRegistry(registry)
    }

    @discardableResult
    public func rename(_ id: ManagedProfile.ID, to name: String) throws -> ManagedProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ManagedProfileError.invalidName
        }

        var registry = try loadRegistry()
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else {
            throw ManagedProfileError.profileNotFound
        }
        registry.profiles[index].name = trimmedName
        let renamedProfile = registry.profiles[index]
        try saveRegistry(registry)
        return renamedProfile
    }

    public func remove(_ id: ManagedProfile.ID) throws {
        var registry = try loadRegistry()
        guard let profile = registry.profiles.first(where: { $0.id == id }) else {
            throw ManagedProfileError.profileNotFound
        }
        registry.profiles.removeAll { $0.id == id }
        if registry.selectedProfileID == id {
            registry.selectedProfileID = registry.profiles.first?.id
        }
        try? FileManager.default.removeItem(at: profile.managedConfigURL.deletingLastPathComponent())
        try saveRegistry(registry)
    }

    @discardableResult
    public func materialize(profile: ManagedProfile) throws -> URL {
        guard FileManager.default.fileExists(atPath: profile.managedConfigURL.path) else {
            throw ManagedProfileError.profileNotFound
        }
        let data = try Data(contentsOf: profile.managedConfigURL)
        try FileManager.default.createDirectory(
            at: runtimeConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: runtimeConfigURL, options: .atomic)
        return runtimeConfigURL
    }

    private func loadRegistry() throws -> Registry {
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            return Registry(profiles: [], selectedProfileID: nil)
        }
        return try JSONDecoder.managedProfiles.decode(Registry.self, from: Data(contentsOf: registryURL))
    }

    private func saveRegistry(_ registry: Registry) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try JSONEncoder.managedProfiles.encode(registry).write(to: registryURL, options: .atomic)
    }
}

private struct Registry: Codable {
    var profiles: [ManagedProfile]
    var selectedProfileID: ManagedProfile.ID?
}

private extension JSONEncoder {
    static var managedProfiles: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var managedProfiles: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
