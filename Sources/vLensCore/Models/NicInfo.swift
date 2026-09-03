import Foundation

/// RVTools vNic tab — physical network adapters (rvtools.txt ~line 3734).
public struct NicInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let device: String
    public let mac: String
    public let linkSpeedMb: Int?
    public let driver: String?

    public init(id: String, hostName: String, device: String, mac: String, linkSpeedMb: Int?, driver: String?) {
        self.id = id
        self.hostName = hostName
        self.device = device
        self.mac = mac
        self.linkSpeedMb = linkSpeedMb
        self.driver = driver
    }
}
