import Foundation

/// Persists saved connection profiles (host/username — never the password,
/// that's Keychain's job via CredentialStoreProtocol) as JSON under
/// Application Support. Small, human-inspectable, no need for anything
/// heavier at this scale.
public struct ConnectionProfileStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = ConnectionProfileStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("vLens", isDirectory: true)
        return dir.appendingPathComponent("connection-profiles.json")
    }

    public func loadAll() -> [ConnectionProfile] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ConnectionProfile].self, from: data)) ?? []
    }

    public func upsert(_ profile: ConnectionProfile) throws {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == profile.id }) {
            all[idx] = profile
        } else {
            all.append(profile)
        }
        try persist(all)
    }

    public func delete(id: UUID) throws {
        var all = loadAll()
        all.removeAll { $0.id == id }
        try persist(all)
    }

    private func persist(_ profiles: [ConnectionProfile]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }
}
