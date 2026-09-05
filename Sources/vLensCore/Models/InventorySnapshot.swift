import Foundation

/// A point-in-time record of `InventorySnapshotMetrics` for one vCenter host,
/// persisted locally by `SnapshotStore` — not RVTools' concept, this app's own
/// "take a snapshot, compare it against a later one" feature (see
/// `SnapshotsTabView`). Nothing to do with vSphere VM snapshots (`VMSnapshotInfo`).
public struct InventorySnapshot: Codable, Identifiable, Sendable {
    public let id: UUID
    public let vCenterHost: String
    public let takenAt: Date
    /// When the underlying inventory data was actually retrieved from
    /// vCenter — distinct from `takenAt` (when this snapshot *record* was
    /// created) because the GUI can keep showing the last successfully
    /// collected data, marked stale, after a refresh fails (see
    /// `ConnectionViewModel.isDataStale`). Taking a snapshot of that stale
    /// data should honestly record how old it really is rather than
    /// implying it's as fresh as the moment the snapshot button was
    /// pressed. `nil` for every snapshot taken before this field existed —
    /// treated as equal to `takenAt` (see `effectiveDataCollectedAt`), since
    /// there was no staleness concept to diverge from back then.
    public let dataCollectedAt: Date?
    /// User-supplied note; falls back to a formatted `takenAt` for display
    /// wherever it's empty/nil.
    public let label: String?
    public let metrics: InventorySnapshotMetrics
    /// Opt-in, off by default — see `SnapshotsTabView`'s "Include full VM
    /// inventory" checkbox. `nil` for every snapshot taken without it
    /// (including all pre-existing snapshots, which decode fine since this
    /// is optional). Only used for the Compare panel's "VM Membership Changes"
    /// added/removed section — deliberately not a field-by-field diff of
    /// every VM, just membership by `vmUUID`.
    public let fullVMList: [VirtualMachineInfo]?

    public init(
        id: UUID = UUID(), vCenterHost: String, takenAt: Date = Date(), dataCollectedAt: Date? = nil,
        label: String?, metrics: InventorySnapshotMetrics, fullVMList: [VirtualMachineInfo]? = nil
    ) {
        self.id = id
        self.vCenterHost = vCenterHost
        self.takenAt = takenAt
        self.dataCollectedAt = dataCollectedAt
        self.label = label
        self.metrics = metrics
        self.fullVMList = fullVMList
    }

    /// `dataCollectedAt` with a sensible fallback for pre-existing snapshots
    /// that predate the field (see its doc comment).
    public var effectiveDataCollectedAt: Date { dataCollectedAt ?? takenAt }

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
