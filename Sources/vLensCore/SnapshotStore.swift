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

    /// Best-effort read for display purposes (the Snapshots tab's list) —
    /// `[]` on any failure, including a corrupt file, since refusing to
    /// show the UI at all over that would be worse. `add`/`delete` use the
    /// stricter `loadForMutation()` below instead, which never silently
    /// treats a corrupt (as opposed to simply absent) file as empty.
    public func loadAll() -> [InventorySnapshot] {
        (try? loadForMutation()) ?? []
    }

    /// Missing file → legitimately empty history, returns `[]`. An
    /// *existing but unreadable/undecodable* file throws instead — found
    /// by an external code review: silently treating corrupt data the same
    /// as "no history" let `add`/`delete` persist right over it with just
    /// the one new/remaining snapshot, discarding everything else that was
    /// actually in the file.
    private func loadForMutation() throws -> [InventorySnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([InventorySnapshot].self, from: data)
    }

    public func add(_ snapshot: InventorySnapshot) throws {
        try withFileLock {
            var all = try loadForMutation()
            all.append(snapshot)
            try persist(all)
        }
    }

    public func delete(id: UUID) throws {
        try withFileLock {
            var all = try loadForMutation()
            all.removeAll { $0.id == id }
            try persist(all)
        }
    }

    /// Bulk delete — one load/persist round trip for the whole set instead
    /// of calling `delete(id:)` in a loop (which would re-read and re-write
    /// the file once per snapshot). Used by the Snapshots tab's multi-select
    /// "Delete Selected" action.
    public func delete(ids: Set<UUID>) throws {
        try withFileLock {
            var all = try loadForMutation()
            all.removeAll { ids.contains($0.id) }
            try persist(all)
        }
    }

    private func persist(_ snapshots: [InventorySnapshot]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Advisory cross-process file lock (POSIX `flock`, held for the
    /// entire load-modify-persist sequence) on a `.lock` sidecar next to
    /// the snapshot file. The GUI and a scheduled `vlens-cli snapshot` run
    /// (Faz 10B's launchd automation) can genuinely execute at the same
    /// time — without this, whichever process's `.atomic` write lands last
    /// silently discards whatever the other one had just added, since both
    /// load the same starting state and neither knows about the other's
    /// change. Found by an external code review. If a lock file can't even
    /// be created, proceeds without locking rather than failing the whole
    /// operation outright — a best-effort safety net for a single-user
    /// desktop app, not a distributed-systems guarantee (e.g. it doesn't
    /// protect against two *different machines* writing to a shared
    /// network folder — `SnapshotPreferencesStore.customStorageDirectory`'s
    /// own doc comment already calls that scenario out of scope).
    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockPath = fileURL.appendingPathExtension("lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            return try body()
        }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
