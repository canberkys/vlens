import Foundation

/// Persists `InventorySnapshot` records as JSON under Application Support —
/// same pattern as `ConnectionProfileStore`. All snapshots for every
/// vCenter host live in one file; callers filter by `vCenterHost`
/// (`ConnectionViewModel.loadSnapshotHistory`) rather than this store
/// splitting files per host, since the whole list is small (a scalar
/// metrics struct per entry, not a full inventory).
public struct SnapshotStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = SnapshotStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// Exposed for "Reveal in Finder" and location-migration in
    /// Preferences — see `SnapshotPreferencesStore.customStorageDirectory`.
    public var url: URL { fileURL }

    public static let fileName = "inventory-snapshots.json"

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("vLens", isDirectory: true)
    }

    public static var defaultURL: URL {
        defaultDirectory.appendingPathComponent(fileName)
    }

    /// `directory` is `SnapshotPreferencesStore.customStorageDirectory` —
    /// `nil` resolves to `defaultURL`.
    public static func url(inDirectory directory: URL?) -> URL {
        guard let directory else { return defaultURL }
        return directory.appendingPathComponent(fileName)
    }

    public func loadAll() -> [InventorySnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([InventorySnapshot].self, from: data)) ?? []
    }

    public func add(_ snapshot: InventorySnapshot) throws {
        var all = loadAll()
        all.append(snapshot)
        try persist(all)
    }

    public func delete(id: UUID) throws {
        var all = loadAll()
        all.removeAll { $0.id == id }
        try persist(all)
    }

    /// Bulk delete — one load/persist round trip for the whole set instead
    /// of calling `delete(id:)` in a loop (which would re-read and re-write
    /// the file once per snapshot). Used by the Snapshots tab's multi-select
    /// "Delete Selected" action.
    public func delete(ids: Set<UUID>) throws {
        var all = loadAll()
        all.removeAll { ids.contains($0.id) }
        try persist(all)
    }

    private func persist(_ snapshots: [InventorySnapshot]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
    }
}
