import Foundation

/// RVTools vNetwork tab — per-VM virtual NIC info (rvtools.txt ~line 1581).
/// Distinct from `NicInfo` (host physical pNICs) and `VMKernelInfo` (host
/// VMkernel adapters) — this is "which port group is this VM's NIC on."
/// `network` prefers the guest-reported name (`guest.net`, requires VMware
/// Tools) over the device-backing resolution when both are available — see
/// `mapVMNetworks` in `helper/main.go`.
public struct VMNetworkInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let nicLabel: String
    public let adapterType: String
    public let network: String
    public let connected: Bool
    public let macAddress: String
    public let ipv4Address: String?
    public let ipv6Address: String?

    public init(
        id: String, vmName: String, powerState: PowerState, nicLabel: String, adapterType: String,
        network: String, connected: Bool, macAddress: String, ipv4Address: String?, ipv6Address: String?
    ) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.nicLabel = nicLabel
        self.adapterType = adapterType
        self.network = network
        self.connected = connected
        self.macAddress = macAddress
        self.ipv4Address = ipv4Address
        self.ipv6Address = ipv6Address
    }
}
