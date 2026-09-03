import Foundation

/// RVTools vSnapshot tab — representative subset (rvtools.txt ~line 2054).
public struct VMSnapshotInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let powerState: PowerState
    public let snapshotName: String
    public let snapshotDescription: String?
    public let createdDate: Date
    public let sizeMiBTotal: Int?
    public let quiesced: Bool
    public let hostName: String
    public let clusterName: String?

    public init(
        id: String, vmName: String, powerState: PowerState, snapshotName: String,
        snapshotDescription: String?, createdDate: Date, sizeMiBTotal: Int?, quiesced: Bool,
        hostName: String, clusterName: String?
    ) {
        self.id = id
        self.vmName = vmName
        self.powerState = powerState
        self.snapshotName = snapshotName
        self.snapshotDescription = snapshotDescription
        self.createdDate = createdDate
        self.sizeMiBTotal = sizeMiBTotal
        self.quiesced = quiesced
        self.hostName = hostName
        self.clusterName = clusterName
    }

    /// vHealth rule #3 ("VM has an active snapshot!") just flags presence,
    /// not age — but a user-configurable age threshold is a natural
    /// extension once vHealth is built, so surface it here now.
    public var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: createdDate, to: Date()).day ?? 0
    }
}
