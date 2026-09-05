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
    /// The VM's immediate containing Folder in the vCenter inventory tree —
    /// distinct from `resourcePoolName` (compute placement). A real vInfo
    /// column, and also feeds `HealthCheckEngine`'s "Inconsistent Folder
    /// Names" rule (RVTools #11).
    public let folderName: String?
    /// Not a vInfo column — only read by `HealthCheckEngine`'s "consolidation
    /// needed" rule (matches this doc comment's own "don't pre-model unread
    /// fields" rule: this one is read).
    public let consolidationNeeded: Bool
    /// Same reasoning — only read by `HealthCheckEngine`'s "Disk I/O
    /// performance tip" rule (RVTools #22). Number of distinct
    /// ParaVirtualSCSIController *devices* registered with the VM, not
    /// disks attached to one.
    public let pvscsiControllerCount: Int

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
        folderName: String? = nil,
        consolidationNeeded: Bool = false,
        pvscsiControllerCount: Int = 0
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
        self.folderName = folderName
        self.consolidationNeeded = consolidationNeeded
        self.pvscsiControllerCount = pvscsiControllerCount
    }
}

public enum PowerState: String, Codable, Sendable {
    case poweredOn
    case poweredOff
    case suspended
}
