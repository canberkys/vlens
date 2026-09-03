import Foundation

/// RVTools dvSwitch tab — distributed virtual switches (rvtools.txt ~line 4083).
public struct DVSwitchInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let uuid: String
    public let numPorts: Int
    public let numHosts: Int
    public let numPortGroups: Int

    public init(id: String, name: String, uuid: String, numPorts: Int, numHosts: Int, numPortGroups: Int) {
        self.id = id
        self.name = name
        self.uuid = uuid
        self.numPorts = numPorts
        self.numHosts = numHosts
        self.numPortGroups = numPortGroups
    }
}
