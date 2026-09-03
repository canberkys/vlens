import Foundation

/// MVP subset of RVTools' vInfo tab. Field names/semantics are defined by the
/// official RVTools reference (see rvtools.txt in the project scratchpad) —
/// extend this incrementally as more vInfo columns are wired up, don't
/// pre-model fields nothing reads yet.
public struct VirtualMachineInfo: Codable, Identifiable, Sendable {
    public var id: String { vmUUID }

    public let name: String
    public let powerState: PowerState
    public let template: Bool
    public let guestOSFullName: String?
    public let cpuCount: Int
    public let memoryMiB: Int
    public let hostName: String
    public let clusterName: String?
    public let resourcePoolName: String?
    public let primaryIPAddress: String?
    public let vmwareToolsStatus: String?
    public let vmUUID: String
    /// Not a vInfo column — only read by `HealthCheckEngine`'s "consolidation
    /// needed" rule (matches this doc comment's own "don't pre-model unread
    /// fields" rule: this one is read).
    public let consolidationNeeded: Bool

    public init(
        name: String,
        powerState: PowerState,
        template: Bool,
        guestOSFullName: String?,
        cpuCount: Int,
        memoryMiB: Int,
        hostName: String,
        clusterName: String?,
        resourcePoolName: String?,
        primaryIPAddress: String?,
        vmwareToolsStatus: String?,
        vmUUID: String,
        consolidationNeeded: Bool = false
    ) {
        self.name = name
        self.powerState = powerState
        self.template = template
        self.guestOSFullName = guestOSFullName
        self.cpuCount = cpuCount
        self.memoryMiB = memoryMiB
        self.hostName = hostName
        self.clusterName = clusterName
        self.resourcePoolName = resourcePoolName
        self.primaryIPAddress = primaryIPAddress
        self.vmwareToolsStatus = vmwareToolsStatus
        self.vmUUID = vmUUID
        self.consolidationNeeded = consolidationNeeded
    }
}

public enum PowerState: String, Codable, Sendable {
    case poweredOn
    case poweredOff
    case suspended
}
