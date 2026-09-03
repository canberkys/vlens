import Foundation

/// JSON contract between the Swift app and the embedded `vlens-helper` (Go/govmomi)
/// binary. One request/response pair per process invocation for the MVP —
/// request goes in on stdin as a single line of JSON, response comes back on
/// stdout as a single line of JSON, the process then exits. Keep this file
/// and `helper/main.go`'s matching structs in sync by hand; there's no
/// codegen for the MVP given the small, fixed surface.
public struct HelperRequest: Codable, Sendable {
    public let action: HelperAction
    public let url: String
    public let username: String
    public let password: String
    public let insecure: Bool
    public let perfIntervalMinutes: Int?

    public init(
        action: HelperAction, url: String, username: String, password: String, insecure: Bool,
        perfIntervalMinutes: Int? = nil
    ) {
        self.action = action
        self.url = url
        self.username = username
        self.password = password
        self.insecure = insecure
        self.perfIntervalMinutes = perfIntervalMinutes
    }
}

public enum HelperAction: String, Codable, Sendable {
    case collectAll
    case getCertificate
    case collectPerformance
}

/// One login, one PropertyCollector pass per object type — every MVP tab's
/// data comes back together. Field names/optionality must match
/// `helper/main.go`'s `helperResponse` struct exactly (Swift's synthesized
/// Codable keys off property names 1:1, no custom CodingKeys here).
public struct HelperResponse: Codable, Sendable {
    public let ok: Bool
    public let error: String?
    public let vms: [VirtualMachineInfo]?
    public let cpus: [VMCpuInfo]?
    public let memory: [VMMemoryInfo]?
    public let disks: [VMDiskInfo]?
    public let snapshots: [VMSnapshotInfo]?
    public let tools: [VMToolsInfo]?
    public let hosts: [HostInfo]?
    public let datastores: [DatastoreInfo]?
    public let clusters: [ClusterInfo]?
    public let licenses: [LicenseInfo]?
    public let vSwitches: [VSwitchInfo]?
    public let ports: [VPortInfo]?
    public let dvSwitches: [DVSwitchInfo]?
    public let dvPorts: [DVPortInfo]?
    public let resourcePools: [ResourcePoolInfo]?
    public let hbas: [HBAInfo]?
    public let nics: [NicInfo]?
    public let vmKernels: [VMKernelInfo]?
    public let multipaths: [MultipathInfo]?
    public let cds: [CDInfo]?
    public let usbs: [USBInfo]?
    public let partitions: [PartitionInfo]?
    public let networks: [VMNetworkInfo]?
    public let performance: [VMPerformanceInfo]?
    public let vCenter: VCenterInfo?
    public let certificate: HelperCertificateInfo?
}

/// Wire shape for `getCertificate` — a raw TLS-layer fingerprint fetch, no
/// vCenter login involved. Mapped into `CertificateFingerprint` +
/// `PendingCertificateApproval` by `ConnectionViewModel`.
public struct HelperCertificateInfo: Codable, Sendable {
    public let sha256Fingerprint: String
    public let subject: String
    public let issuer: String
    public let notAfter: String
}

/// Everything `collectAll` returns, bundled for the app layer.
public struct CollectedInventory: Sendable {
    public let vms: [VirtualMachineInfo]
    public let cpus: [VMCpuInfo]
    public let memory: [VMMemoryInfo]
    public let disks: [VMDiskInfo]
    public let snapshots: [VMSnapshotInfo]
    public let tools: [VMToolsInfo]
    public let hosts: [HostInfo]
    public let datastores: [DatastoreInfo]
    public let clusters: [ClusterInfo]
    public let licenses: [LicenseInfo]
    public let vSwitches: [VSwitchInfo]
    public let ports: [VPortInfo]
    public let dvSwitches: [DVSwitchInfo]
    public let dvPorts: [DVPortInfo]
    public let resourcePools: [ResourcePoolInfo]
    public let hbas: [HBAInfo]
    public let nics: [NicInfo]
    public let vmKernels: [VMKernelInfo]
    public let multipaths: [MultipathInfo]
    public let cds: [CDInfo]
    public let usbs: [USBInfo]
    public let partitions: [PartitionInfo]
    public let networks: [VMNetworkInfo]
    public let vCenter: VCenterInfo?
}

public enum HelperClientError: Error, Sendable {
    case helperBinaryNotFound
    case processFailed(exitCode: Int32, stderr: String)
    case emptyResponse
    case decodingFailed(String)
    case helperReportedError(String)
}
