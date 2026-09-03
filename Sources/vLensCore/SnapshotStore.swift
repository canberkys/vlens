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

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("vLens", isDirectory: true)
        return dir.appendingPathComponent("inventory-snapshots.json")
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

    private func persist(_ snapshots: [InventorySnapshot]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
    }
}
