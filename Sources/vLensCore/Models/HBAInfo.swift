import Foundation

/// RVTools vHBA tab — host bus adapters (rvtools.txt ~line 3670).
public struct HBAInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let device: String
    public let model: String
    public let driver: String
    public let status: String

    public init(id: String, hostName: String, device: String, model: String, driver: String, status: String) {
        self.id = id
        self.hostName = hostName
        self.device = device
        self.model = model
        self.driver = driver
        self.status = status
    }
}
