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
    /// Same reasoning — only read by `HealthCheckEngine`'s "VM config status"
    /// rule (RVTools #15). `ManagedEntity.configStatus`, not an event stream —
    /// same field Host/Cluster already expose as a real column.
    public let configStatus: EntityStatus
    /// vSphere Tags (CIS REST Tagging API) and Custom Attributes
    /// (`ManagedEntity.customValue`, already formatted "Key: Value") —
    /// export-only, vInfo is already at its 10-column ceiling.
    public let tags: [String]
    public let customAttributes: [String]
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
        pvscsiControllerCount: Int = 0,
        configStatus: EntityStatus = .green,
        tags: [String] = [],
        customAttributes: [String] = []
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
        self.configStatus = configStatus
        self.tags = tags
        self.customAttributes = customAttributes
    }
}

extension VirtualMachineInfo {
    private enum CodingKeys: String, CodingKey {
        case name, powerState, template, guestOSFullName, cpuCount, memoryMiB, hostName,
             clusterName, resourcePoolName, primaryIPAddress, vmwareToolsStatus, vmUUID,
             folderName, consolidationNeeded, configStatus, tags, customAttributes,
             pvscsiControllerCount
    }

    /// Hand-written only so fields added after v1.0.0 decode with a default
    /// when absent. `InventorySnapshot.fullVMList` persists this type to
    /// disk, and a snapshot saved by an older version lacks those keys —
    /// with synthesized decoding one such entry failed the whole
    /// snapshots.json (empty Snapshots tab, add/delete throwing). Any field
    /// added here later must use `decodeIfPresent` too.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        powerState = try c.decode(PowerState.self, forKey: .powerState)
        template = try c.decode(Bool.self, forKey: .template)
        guestOSFullName = try c.decodeIfPresent(String.self, forKey: .guestOSFullName)
        cpuCount = try c.decode(Int.self, forKey: .cpuCount)
        memoryMiB = try c.decode(Int.self, forKey: .memoryMiB)
        hostName = try c.decode(String.self, forKey: .hostName)
        clusterName = try c.decodeIfPresent(String.self, forKey: .clusterName)
        resourcePoolName = try c.decodeIfPresent(String.self, forKey: .resourcePoolName)
        primaryIPAddress = try c.decodeIfPresent(String.self, forKey: .primaryIPAddress)
        vmwareToolsStatus = try c.decodeIfPresent(String.self, forKey: .vmwareToolsStatus)
        vmUUID = try c.decode(String.self, forKey: .vmUUID)
        folderName = try c.decodeIfPresent(String.self, forKey: .folderName)
        consolidationNeeded = try c.decodeIfPresent(Bool.self, forKey: .consolidationNeeded) ?? false
        configStatus = try c.decodeIfPresent(EntityStatus.self, forKey: .configStatus) ?? .gray
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        customAttributes = try c.decodeIfPresent([String].self, forKey: .customAttributes) ?? []
        pvscsiControllerCount = try c.decodeIfPresent(Int.self, forKey: .pvscsiControllerCount) ?? 0
    }
}

public enum PowerState: String, Codable, Sendable {
    case poweredOn
    case poweredOff
    case suspended
}
