import Foundation

/// RVTools vDisk tab — representative subset (rvtools.txt ~line 1174).
public struct VMDiskInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let diskLabel: String
    public let capacityMiB: Int
    public let thinProvisioned: Bool
    public let diskMode: String
    public let controller: String
    public let unitNumber: Int
    public let datastorePath: String
    public let hostName: String

    public init(
        id: String, vmName: String, powerState: PowerState, diskLabel: String, capacityMiB: Int,
        thinProvisioned: Bool, diskMode: String, controller: String, unitNumber: Int,
        datastorePath: String, hostName: String
    ) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.diskLabel = diskLabel
        self.capacityMiB = capacityMiB
        self.thinProvisioned = thinProvisioned
        self.diskMode = diskMode
        self.controller = controller
        self.unitNumber = unitNumber
        self.datastorePath = datastorePath
        self.hostName = hostName
    }
}
