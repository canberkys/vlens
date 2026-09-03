import Foundation

/// A point-in-time record of `InventorySnapshotMetrics` for one vCenter host,
/// persisted locally by `SnapshotStore` — not RVTools' concept, this app's own
/// "take a snapshot, compare it against a later one" feature (see
/// `SnapshotsTabView`). Nothing to do with vSphere VM snapshots (`VMSnapshotInfo`).
public struct InventorySnapshot: Codable, Identifiable, Sendable {
    public let id: UUID
    public let vCenterHost: String
    public let takenAt: Date
    /// User-supplied note; falls back to a formatted `takenAt` for display
    /// wherever it's empty/nil.
    public let label: String?
    public let metrics: InventorySnapshotMetrics

    public init(id: UUID = UUID(), vCenterHost: String, takenAt: Date = Date(), label: String?, metrics: InventorySnapshotMetrics) {
        self.id = id
        self.vCenterHost = vCenterHost
        self.takenAt = takenAt
        self.label = label
        self.metrics = metrics
    }

    /// Display label wherever a UI needs one — the user's note if they gave
    /// one, otherwise a formatted timestamp.
    public var displayLabel: String {
        if let label, !label.isEmpty { return label }
        return takenAt.formatted(date: .abbreviated, time: .shortened)
    }
}
