import Foundation

/// RVTools vSwitch tab — standard (per-host) virtual switches
/// (rvtools.txt ~line 3798).
public struct VSwitchInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let name: String
    public let numPorts: Int
    public let numPortsAvailable: Int
    public let mtu: Int
    public let numUplinks: Int
    public let numPortGroups: Int

    public init(
        id: String, hostName: String, name: String, numPorts: Int, numPortsAvailable: Int,
        mtu: Int, numUplinks: Int, numPortGroups: Int
    ) {
        self.id = id
        self.hostName = hostName
        self.name = name
        self.numPorts = numPorts
        self.numPortsAvailable = numPortsAvailable
        self.mtu = mtu
        self.numUplinks = numUplinks
        self.numPortGroups = numPortGroups
    }
}
