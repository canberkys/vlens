import Foundation

/// RVTools vMemory tab — representative subset (rvtools.txt ~line 966).
public struct VMMemoryInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let sizeMiB: Int
    public let overheadMiB: Int?
    public let consumedMiB: Int?
    public let activeMiB: Int?
    public let sharedMiB: Int?
    public let swappedMiB: Int?
    public let balloonedMiB: Int?
    public let reservationMiB: Int
    public let limitMiB: Int // -1 == no limit
    public let hotAddEnabled: Bool
    public let hostName: String
    public let clusterName: String?

    public init(
        id: String, vmName: String, powerState: PowerState, sizeMiB: Int, overheadMiB: Int?,
        consumedMiB: Int?, activeMiB: Int?, sharedMiB: Int?, swappedMiB: Int?, balloonedMiB: Int?,
        reservationMiB: Int, limitMiB: Int, hotAddEnabled: Bool, hostName: String, clusterName: String?
    ) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.sizeMiB = sizeMiB
        self.overheadMiB = overheadMiB
        self.consumedMiB = consumedMiB
        self.activeMiB = activeMiB
        self.sharedMiB = sharedMiB
        self.swappedMiB = swappedMiB
        self.balloonedMiB = balloonedMiB
        self.reservationMiB = reservationMiB
        self.limitMiB = limitMiB
        self.hotAddEnabled = hotAddEnabled
        self.hostName = hostName
        self.clusterName = clusterName
    }
}
