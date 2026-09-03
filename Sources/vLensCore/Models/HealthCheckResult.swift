import Foundation

/// One finding on the vHealth tab. RVTools documents 24 built-in rules
/// (rvtools.txt, vHealth section) — this implements the 9 that are
/// computable from data already modeled elsewhere (vSnapshot/vTools/
/// vDatastore/vHost/vCPU/vCD/vPartition/vMultipath), not the full set. See
/// HealthCheckEngine for which rule maps to which RVTools rule number.
public struct HealthCheckResult: Identifiable, Sendable {
    public let id: String
    public let severity: EntityStatus
    public let rule: String
    public let message: String
    public let relatedObject: String

    public init(id: String, severity: EntityStatus, rule: String, message: String, relatedObject: String) {
        self.id = id
        self.severity = severity
        self.rule = rule
        self.message = message
        self.relatedObject = relatedObject
    }
}

public struct HealthCheckThresholds: Equatable, Sendable {
    public var datastoreFreeSpacePercent: Double
    public var vCPUsPerCoreWarning: Double
    public var guestDiskFreeSpacePercent: Double
    public var maxVMsPerDatastore: Int

    public init(
        datastoreFreeSpacePercent: Double = 10, vCPUsPerCoreWarning: Double = 4,
        guestDiskFreeSpacePercent: Double = 10, maxVMsPerDatastore: Int = 30
    ) {
        self.datastoreFreeSpacePercent = datastoreFreeSpacePercent
        self.vCPUsPerCoreWarning = vCPUsPerCoreWarning
        self.guestDiskFreeSpacePercent = guestDiskFreeSpacePercent
        self.maxVMsPerDatastore = maxVMsPerDatastore
    }
}
