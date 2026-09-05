import Foundation

/// RVTools vFloppy tab — floppy devices (rvtools.txt ~line 1108). Also feeds
/// vHealth's #2 "VM has a Floppy device connected!" rule.
public struct FloppyInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let connected: Bool

    public init(id: String, vmName: String, powerState: PowerState, connected: Bool) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.connected = connected
    }
}
