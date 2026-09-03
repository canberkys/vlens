import Foundation

/// RVTools vTools tab — representative subset (rvtools.txt ~line 2181).
public struct VMToolsInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let hardwareVersion: String
    public let toolsStatus: ToolsStatus
    public let toolsVersion: String?
    public let hostName: String
    public let clusterName: String?

    public init(
        id: String, vmName: String, powerState: PowerState, hardwareVersion: String,
        toolsStatus: ToolsStatus, toolsVersion: String?, hostName: String, clusterName: String?
    ) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.hardwareVersion = hardwareVersion
        self.toolsStatus = toolsStatus
        self.toolsVersion = toolsVersion
        self.hostName = hostName
        self.clusterName = clusterName
    }
}

public enum ToolsStatus: String, Codable, Sendable {
    case toolsNotInstalled
    case toolsNotRunning
    case toolsOk
    case toolsOld
}
