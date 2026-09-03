import Foundation

/// RVTools vMultipath tab — storage multipathing (rvtools.txt ~line 4776).
/// Doesn't attempt to extract the path-selection `Policy` field — that's a
/// type-switch over ~4 concrete vim25 policy types for a display string of
/// low value on this already-niche tab; `operationalState` covers the
/// actually useful signal (degraded/dead paths).
public struct MultipathInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let disk: String
    public let displayName: String
    public let numPaths: Int
    public let operationalState: [String]
    public let vendor: String
    public let model: String

    public init(
        id: String, hostName: String, disk: String, displayName: String, numPaths: Int,
        operationalState: [String], vendor: String, model: String
    ) {
        self.id = id
        self.hostName = hostName
        self.disk = disk
        self.displayName = displayName
        self.numPaths = numPaths
        self.operationalState = operationalState
        self.vendor = vendor
        self.model = model
    }
}
