import Foundation

/// Curated, cheap-to-compute aggregate counts — not a full inventory dump.
/// Every field derives from arrays already sitting in memory
/// (`ConnectionViewModel`'s already-collected tabs), so taking a snapshot
/// costs no extra vCenter round trip. See `InventorySnapshot` for the
/// wrapper this gets stored in, and `SnapshotMetricDescriptor` for how each
/// field is labeled/compared in the Snapshots tab's Compare panel.
public struct InventorySnapshotMetrics: Codable, Equatable, Sendable {
    public let vmCountTotal: Int
    public let vmCountPoweredOn: Int
    public let vmCountPoweredOff: Int
    public let hostCount: Int
    public let clusterCount: Int
    public let datastoreCount: Int
    /// The single most-full datastore's free % — not an average, since an
    /// average can hide the one datastore that's actually about to fill up.
    public let datastoreMinFreePercent: Double?
    public let activeSnapshotCount: Int
    public let toolsNotOKCount: Int
    public let vHealthRedCount: Int
    public let vHealthYellowCount: Int

    public init(
        vmCountTotal: Int, vmCountPoweredOn: Int, vmCountPoweredOff: Int, hostCount: Int,
        clusterCount: Int, datastoreCount: Int, datastoreMinFreePercent: Double?,
        activeSnapshotCount: Int, toolsNotOKCount: Int, vHealthRedCount: Int, vHealthYellowCount: Int
    ) {
        self.vmCountTotal = vmCountTotal
        self.vmCountPoweredOn = vmCountPoweredOn
        self.vmCountPoweredOff = vmCountPoweredOff
        self.hostCount = hostCount
        self.clusterCount = clusterCount
        self.datastoreCount = datastoreCount
        self.datastoreMinFreePercent = datastoreMinFreePercent
        self.activeSnapshotCount = activeSnapshotCount
        self.toolsNotOKCount = toolsNotOKCount
        self.vHealthRedCount = vHealthRedCount
        self.vHealthYellowCount = vHealthYellowCount
    }

    public static func compute(
        vms: [VirtualMachineInfo], hosts: [HostInfo], clusters: [ClusterInfo],
        datastores: [DatastoreInfo], snapshots: [VMSnapshotInfo], tools: [VMToolsInfo],
        healthChecks: [HealthCheckResult]
    ) -> InventorySnapshotMetrics {
        InventorySnapshotMetrics(
            vmCountTotal: vms.count,
            vmCountPoweredOn: vms.filter { $0.powerState == .poweredOn }.count,
            vmCountPoweredOff: vms.filter { $0.powerState == .poweredOff }.count,
            hostCount: hosts.count,
            clusterCount: clusters.count,
            datastoreCount: datastores.count,
            datastoreMinFreePercent: datastores.map(\.freePercent).min(),
            activeSnapshotCount: snapshots.count,
            toolsNotOKCount: tools.filter { $0.toolsStatus != .toolsOk }.count,
            vHealthRedCount: healthChecks.filter { $0.severity == .red }.count,
            vHealthYellowCount: healthChecks.filter { $0.severity == .yellow }.count
        )
    }
}

/// Which direction is an *improvement* for a given metric — the Compare
/// panel colors a delta green/red based on this, not just on the sign of
/// the change. `neutral` metrics (e.g. VM count) are shown but not colored
/// — growth isn't inherently good or bad.
public enum MetricComparisonDirection: Sendable {
    case higherIsBetter
    case lowerIsBetter
    case neutral
}

/// One row in the Compare panel / Preferences' "Snapshot comparison
/// metrics" toggle list. `value` reads the field off `InventorySnapshotMetrics`
/// as a `Double` (Int fields promoted) so the Compare panel has one code path
/// regardless of the underlying field's type.
public struct SnapshotMetricDescriptor: Sendable {
    public let key: String
    public let label: String
    public let direction: MetricComparisonDirection
    public let value: @Sendable (InventorySnapshotMetrics) -> Double?
    /// Shown as a hover tooltip next to the toggle in Preferences — these
    /// metrics have no other explanation in the UI besides the label itself.
    public let helpText: String

    public static let all: [SnapshotMetricDescriptor] = [
        SnapshotMetricDescriptor(
            key: "vmCountTotal", label: "Total VMs", direction: .neutral, value: { Double($0.vmCountTotal) },
            helpText: "Every VM registered in the vCenter, powered on or off."
        ),
        SnapshotMetricDescriptor(
            key: "vmCountPoweredOn", label: "Powered-On VMs", direction: .neutral, value: { Double($0.vmCountPoweredOn) },
            helpText: "VMs currently running."
        ),
        SnapshotMetricDescriptor(
            key: "vmCountPoweredOff", label: "Powered-Off VMs", direction: .neutral, value: { Double($0.vmCountPoweredOff) },
            helpText: "VMs currently shut down."
        ),
        SnapshotMetricDescriptor(
            key: "hostCount", label: "Hosts", direction: .neutral, value: { Double($0.hostCount) },
            helpText: "ESXi hosts managed by this vCenter."
        ),
        SnapshotMetricDescriptor(
            key: "clusterCount", label: "Clusters", direction: .neutral, value: { Double($0.clusterCount) },
            helpText: "vSphere clusters."
        ),
        SnapshotMetricDescriptor(
            key: "datastoreCount", label: "Datastores", direction: .neutral, value: { Double($0.datastoreCount) },
            helpText: "Datastores visible to this vCenter."
        ),
        SnapshotMetricDescriptor(
            key: "datastoreMinFreePercent", label: "Lowest Datastore Free %", direction: .higherIsBetter,
            value: { $0.datastoreMinFreePercent },
            helpText: "The single most-full datastore's free space % — not an average, so one nearly-full datastore can't hide behind healthy ones."
        ),
        SnapshotMetricDescriptor(
            key: "activeSnapshotCount", label: "Active Snapshots", direction: .lowerIsBetter, value: { Double($0.activeSnapshotCount) },
            helpText: "Active vSphere VM snapshots across all VMs — the vSnapshot tab's concept, unrelated to this feature's own \"Snapshots.\""
        ),
        SnapshotMetricDescriptor(
            key: "toolsNotOKCount", label: "VMs with Tools Issues", direction: .lowerIsBetter, value: { Double($0.toolsNotOKCount) },
            helpText: "VMs where VMware Tools isn't installed, isn't running, or is out of date."
        ),
        SnapshotMetricDescriptor(
            key: "vHealthRedCount", label: "vHealth Red Findings", direction: .lowerIsBetter, value: { Double($0.vHealthRedCount) },
            helpText: "Red-severity findings on the vHealth tab at the time of the snapshot."
        ),
        SnapshotMetricDescriptor(
            key: "vHealthYellowCount", label: "vHealth Yellow Findings", direction: .lowerIsBetter, value: { Double($0.vHealthYellowCount) },
            helpText: "Yellow-severity findings on the vHealth tab at the time of the snapshot."
        )
    ]
}
