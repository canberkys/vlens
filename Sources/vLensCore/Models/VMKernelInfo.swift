import Foundation

/// RVTools vSC+VMK tab — VMkernel network adapters (rvtools.txt ~line 3956,
/// "vSC+VMK"). Named `VMKernelInfo` rather than matching the tab's odd
/// "vSC+VMK" label directly — Service Console adapters are legacy
/// (pre-ESXi 5.0) and don't apply to any environment this app targets.
public struct VMKernelInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let device: String
    public let portGroup: String
    public let ipAddress: String?
    public let mac: String

    public init(id: String, hostName: String, device: String, portGroup: String, ipAddress: String?, mac: String) {
        self.id = id
        self.hostName = hostName
        self.device = device
        self.portGroup = portGroup
        self.ipAddress = ipAddress
        self.mac = mac
    }
}
