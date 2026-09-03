import Foundation

/// RVTools vCPU tab — representative subset (see rvtools.txt around line 787
/// for the full documented column list; extend on demand, don't pre-model
/// fields nothing reads yet).
public struct VMCpuInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let cpuCount: Int
    public let sockets: Int
    public let coresPerSocket: Int
    public let overallUsageMHz: Int?
    public let reservationMHz: Int
    public let limitMHz: Int // -1 == no limit, matches RVTools' own convention
    public let hotAddEnabled: Bool
    public let hotRemoveEnabled: Bool
    public let hostName: String
    public let clusterName: String?

    public init(
        id: String, vmName: String, powerState: PowerState, cpuCount: Int, sockets: Int,
        coresPerSocket: Int, overallUsageMHz: Int?, reservationMHz: Int, limitMHz: Int,
        hotAddEnabled: Bool, hotRemoveEnabled: Bool, hostName: String, clusterName: String?
    ) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.cpuCount = cpuCount
        self.sockets = sockets
        self.coresPerSocket = coresPerSocket
        self.overallUsageMHz = overallUsageMHz
        self.reservationMHz = reservationMHz
        self.limitMHz = limitMHz
        self.hotAddEnabled = hotAddEnabled
        self.hotRemoveEnabled = hotRemoveEnabled
        self.hostName = hostName
        self.clusterName = clusterName
    }
}
