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
    /// Opt-in, off by default — see `SnapshotsTabView`'s "Include full VM
    /// inventory" checkbox. `nil` for every snapshot taken without it
    /// (including all pre-existing snapshots, which decode fine since this
    /// is optional). Only used for the Compare panel's "VM Changes"
    /// added/removed section — deliberately not a field-by-field diff of
    /// every VM, just membership by `vmUUID`.
    public let fullVMList: [VirtualMachineInfo]?

    public init(
        id: UUID = UUID(), vCenterHost: String, takenAt: Date = Date(), label: String?,
        metrics: InventorySnapshotMetrics, fullVMList: [VirtualMachineInfo]? = nil
    ) {
        self.id = id
        self.vCenterHost = vCenterHost
        self.takenAt = takenAt
        self.label = label
        self.metrics = metrics
        self.fullVMList = fullVMList
    }

    /// Display label wherever a UI needs one — the user's note if they gave
    /// one, otherwise a formatted timestamp. Uses `.standard` time style
    /// (includes seconds) rather than `.shortened` specifically so two
    /// unlabeled snapshots taken close together (a real, common case — e.g.
    /// testing the Compare panel, or a scripted before/after capture) don't
    /// render as visually identical minute-granularity timestamps.
    public var displayLabel: String {
        if let label, !label.isEmpty { return label }
        return takenAt.formatted(date: .abbreviated, time: .standard)
    }
}
