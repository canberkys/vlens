import Foundation

/// RVTools vCluster tab — representative subset (rvtools.txt ~line 3051).
public struct ClusterInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let configStatus: EntityStatus
    public let numHosts: Int
    public let numEffectiveHosts: Int
    public let totalCpuMHz: Int
    public let totalMemoryMiB: Int
    public let haEnabled: Bool
    public let admissionControlEnabled: Bool
    public let drsEnabled: Bool
    public let drsDefaultVMBehavior: String?

    public init(
        id: String, name: String, configStatus: EntityStatus, numHosts: Int,
        numEffectiveHosts: Int, totalCpuMHz: Int, totalMemoryMiB: Int, haEnabled: Bool,
        admissionControlEnabled: Bool, drsEnabled: Bool, drsDefaultVMBehavior: String?
    ) {
        self.id = id
        self.name = name
        self.configStatus = configStatus
        self.numHosts = numHosts
        self.numEffectiveHosts = numEffectiveHosts
        self.totalCpuMHz = totalCpuMHz
        self.totalMemoryMiB = totalMemoryMiB
        self.haEnabled = haEnabled
        self.admissionControlEnabled = admissionControlEnabled
        self.drsEnabled = drsEnabled
        self.drsDefaultVMBehavior = drsDefaultVMBehavior
    }
}
