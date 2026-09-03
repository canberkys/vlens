import Foundation

/// RVTools vCD tab — CD/DVD drives (rvtools.txt ~line 1786). Exactly one of
/// `isoPath`/`deviceName` is set depending on backing type (ISO file vs.
/// physical/passthrough device); both nil is possible for other backing
/// kinds this MVP doesn't distinguish.
public struct CDInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let connected: Bool
    public let isoPath: String?
    public let deviceName: String?

    public init(id: String, vmName: String, powerState: PowerState, connected: Bool, isoPath: String?, deviceName: String?) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.connected = connected
        self.isoPath = isoPath
        self.deviceName = deviceName
    }
}
