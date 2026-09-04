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
    /// Only meaningful for `.getCertificate` (a credential-free probe with
    /// nothing to pin against yet). `.collectAll`/`.collectPerformance`
    /// ignore this on the Go side and require `expectedFingerprint`
    /// instead — see `helper/main.go`'s `newPinnedClient` doc comment for
    /// why a blanket-insecure authenticated connection was a real
    /// vulnerability (the fingerprint check and the credentialed login used
    /// to be two unrelated TLS connections).
    public let insecure: Bool
    /// The already-pinned `CertificateFingerprint.displayValue` for this
    /// host — required for `.collectAll`/`.collectPerformance`, so the Go
    /// helper can bind the actual login connection to the certificate that
    /// was verified, via govmomi's own `soap.Client.SetThumbprint`.
    public let expectedFingerprint: String?
    public let perfIntervalMinutes: Int?

    public init(
        action: HelperAction, url: String, username: String, password: String, insecure: Bool,
        expectedFingerprint: String? = nil, perfIntervalMinutes: Int? = nil
    ) {
        self.action = action
        self.url = url
        self.username = username
        self.password = password
        self.insecure = insecure
        self.expectedFingerprint = expectedFingerprint
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
    public let vApps: [VAppInfo]?
    public let hbas: [HBAInfo]?
    public let nics: [NicInfo]?
    public let vmKernels: [VMKernelInfo]?
    public let multipaths: [MultipathInfo]?
    public let cds: [CDInfo]?
    public let usbs: [USBInfo]?
    public let partitions: [PartitionInfo]?
    public let networks: [VMNetworkInfo]?
    public let performance: [VMPerformanceInfo]?
    public let performanceCoverage: PerformanceCoverage?
    public let vCenter: VCenterInfo?
    public let certificate: HelperCertificateInfo?
}

/// Whether `collectPerformance` actually reached every powered-on VM.
/// `complete == false` means a batched QueryPerf request failed partway
/// through — `collectedVMCount` says how many VMs got data before that
/// (0 if the very first batch failed), and `error` carries the real reason.
/// Without this, a batch failure and a fully-successful-but-empty
/// collection used to be indistinguishable — both just looked like a plain,
/// possibly-empty list.
public struct PerformanceCoverage: Codable, Sendable {
    public let requestedVMCount: Int
    public let collectedVMCount: Int
    public let complete: Bool
    public let error: String?
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
    public let vApps: [VAppInfo]
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
