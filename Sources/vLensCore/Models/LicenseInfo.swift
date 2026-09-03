import Foundation

/// RVTools vLicense tab — representative subset (rvtools.txt ~line 4909).
/// Requires elevated vCenter permissions to see at all (RVTools' own docs
/// note the same restriction for read-only accounts) — the Go helper
/// leaves this array empty rather than failing the whole collection when
/// the license API call is denied.
public struct LicenseInfo: Codable, Identifiable, Sendable {
    public var id: String { key }
    public let name: String
    public let key: String
    public let labels: [String]
    public let costUnit: String
    public let total: Int
    public let used: Int
    public let expirationDate: String?
    public let features: [String]

    public init(
        name: String, key: String, labels: [String], costUnit: String,
        total: Int, used: Int, expirationDate: String?, features: [String]
    ) {
        self.name = name
        self.key = key
        self.labels = labels
        self.costUnit = costUnit
        self.total = total
        self.used = used
        self.expirationDate = expirationDate
        self.features = features
    }
}
