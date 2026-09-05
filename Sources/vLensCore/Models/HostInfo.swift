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
    /// The actual ESXi build number (e.g. "24022515") — distinct from
    /// `esxVersion`'s dotted release version (e.g. "8.0.3"): two hosts can
    /// report the same version while being on different patch builds, and
    /// version alone can't be checked against a specific advisory/patch
    /// level. Same `AboutInfo.Build` field `VCenterInfo.build` already
    /// reads for vCenter itself, just host-scoped here.
    public let esxBuild: String
    public let vendor: String?
    public let model: String?
    public let maintenanceMode: Bool
    /// Not vHost columns — only read by vHealth's ESXi Shell/SSH/NTP rules
    /// (RVTools #20/#21/#17). Service keys: "TSM" (ESXi Shell), "TSM-SSH"
    /// (SSH), "ntpd" (NTP daemon).
    public let esxiShellEnabled: Bool
    public let sshEnabled: Bool
    public let ntpdRunning: Bool
    public let ntpServerCount: Int
    /// Not a vHost column yet — only read by vHealth's #24 rule. `nil` if
    /// the host's certificate couldn't be read (see `helper/main.go`'s
    /// `collectHosts`, which tolerates that rather than failing collectAll).
    public let certNotAfter: Date?

    public init(
        id: String, name: String, datacenterName: String?, clusterName: String?,
        configStatus: EntityStatus, cpuModel: String, cpuMhz: Int, numCpuCores: Int,
        numCpuThreads: Int, cpuUsagePercent: Double?, memoryTotalMiB: Int,
        memoryUsagePercent: Double?, numNics: Int, numHbas: Int, numVMsTotal: Int,
        numVMsRunning: Int, esxVersion: String, esxBuild: String, vendor: String?, model: String?,
        maintenanceMode: Bool, esxiShellEnabled: Bool = false, sshEnabled: Bool = false,
        ntpdRunning: Bool = true, ntpServerCount: Int = 1, certNotAfter: Date? = nil
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
        self.esxBuild = esxBuild
        self.vendor = vendor
        self.model = model
        self.maintenanceMode = maintenanceMode
        self.esxiShellEnabled = esxiShellEnabled
        self.sshEnabled = sshEnabled
        self.ntpdRunning = ntpdRunning
        self.ntpServerCount = ntpServerCount
        self.certNotAfter = certNotAfter
    }
}

/// Shared by vInfo/vHost/vCluster/vDatastore config-status columns in RVTools.
public enum EntityStatus: String, Codable, Sendable {
    case red, yellow, green, gray
}
