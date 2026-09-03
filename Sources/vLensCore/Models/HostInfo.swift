import Foundation

/// RVTools vHost tab — representative subset (rvtools.txt ~line 3309).
public struct HostInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let datacenterName: String?
    public let clusterName: String?
    public let configStatus: EntityStatus
    public let cpuModel: String
    public let cpuMhz: Int
    public let numCpuCores: Int
    public let numCpuThreads: Int
    public let cpuUsagePercent: Double?
    public let memoryTotalMiB: Int
    public let memoryUsagePercent: Double?
    public let numNics: Int
    public let numHbas: Int
    public let numVMsTotal: Int
    public let numVMsRunning: Int
    public let esxVersion: String
    public let vendor: String?
    public let model: String?
    public let maintenanceMode: Bool

    public init(
        id: String, name: String, datacenterName: String?, clusterName: String?,
        configStatus: EntityStatus, cpuModel: String, cpuMhz: Int, numCpuCores: Int,
        numCpuThreads: Int, cpuUsagePercent: Double?, memoryTotalMiB: Int,
        memoryUsagePercent: Double?, numNics: Int, numHbas: Int, numVMsTotal: Int,
        numVMsRunning: Int, esxVersion: String, vendor: String?, model: String?,
        maintenanceMode: Bool
    ) {
        self.id = id
        self.name = name
        self.datacenterName = datacenterName
        self.clusterName = clusterName
        self.configStatus = configStatus
        self.cpuModel = cpuModel
        self.cpuMhz = cpuMhz
        self.numCpuCores = numCpuCores
        self.numCpuThreads = numCpuThreads
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryTotalMiB = memoryTotalMiB
        self.memoryUsagePercent = memoryUsagePercent
        self.numNics = numNics
        self.numHbas = numHbas
        self.numVMsTotal = numVMsTotal
        self.numVMsRunning = numVMsRunning
        self.esxVersion = esxVersion
        self.vendor = vendor
        self.model = model
        self.maintenanceMode = maintenanceMode
    }
}

/// Shared by vInfo/vHost/vCluster/vDatastore config-status columns in RVTools.
public enum EntityStatus: String, Codable, Sendable {
    case red, yellow, green, gray
}
