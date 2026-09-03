import Foundation

/// RVTools vPort tab — standard (per-host) port groups (rvtools.txt ~line 3930).
/// Property name `vlanId` (not `vlanID`) deliberately matches `helper/main.go`'s
/// `json:"vlanId"` tag exactly — Swift's synthesized Codable keys off property
/// names 1:1, no custom CodingKeys in this codebase.
public struct VPortInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let switchName: String
    public let name: String
    public let vlanId: Int

    public init(id: String, hostName: String, switchName: String, name: String, vlanId: Int) {
        self.id = id
        self.hostName = hostName
        self.switchName = switchName
        self.name = name
        self.vlanId = vlanId
    }
}
