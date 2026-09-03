import Foundation

/// RVTools vUSB tab — USB devices (rvtools.txt ~line 1913).
public struct USBInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let connected: Bool
    public let vendor: Int?
    public let product: Int?

    public init(id: String, vmName: String, powerState: PowerState, connected: Bool, vendor: Int?, product: Int?) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.connected = connected
        self.vendor = vendor
        self.product = product
    }
}
