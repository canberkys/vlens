import Foundation

/// RVTools dvPort tab — distributed port groups (rvtools.txt ~line 4335).
/// `vlanId` is nil for anything beyond a single VLAN ID assignment (trunk
/// mode, private VLANs) — the Go collector only handles the common typed
/// case and leaves the rest unset rather than guessing (see
/// `helper/main.go`'s `collectDVPortgroups`).
public struct DVPortInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let switchName: String
    public let numPorts: Int
    public let vlanId: Int?

    public init(id: String, name: String, switchName: String, numPorts: Int, vlanId: Int?) {
        self.id = id
        self.name = name
        self.switchName = switchName
        self.numPorts = numPorts
        self.vlanId = vlanId
    }
}
