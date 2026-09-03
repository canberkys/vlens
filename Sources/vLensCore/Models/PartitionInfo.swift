import Foundation

/// RVTools vPartition tab — guest disk partitions (rvtools.txt ~line 1448).
/// Requires VMware Tools running and reporting guest disk usage
/// (`guest.disk`) — VMs without Tools, or Tools that haven't reported yet,
/// simply contribute no rows here.
public struct PartitionInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let diskPath: String
    public let capacityMiB: Int
    public let freeMiB: Int

    public init(id: String, vmName: String, diskPath: String, capacityMiB: Int, freeMiB: Int) {
        self.id = id
        self.vmName = vmName
        self.diskPath = diskPath
        self.capacityMiB = capacityMiB
        self.freeMiB = freeMiB
    }

    public var freePercent: Double {
        guard capacityMiB > 0 else { return 0 }
        return (Double(freeMiB) / Double(capacityMiB)) * 100
    }
}
