import Foundation

/// RVTools vDatastore tab — representative subset (rvtools.txt ~line 4619).
public struct DatastoreInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: String // e.g. VMFS, NFS
    public let capacityMiB: Int
    public let freeMiB: Int
    public let numVMsTotal: Int
    public let numHostsConnected: Int
    /// `ManagedEntity.configStatus` — feeds `HealthCheckEngine`'s "Datastore
    /// config status" rule (RVTools #19), and is also a real vDatastore
    /// column (RVTools' own reference documents one).
    public let configStatus: EntityStatus
    public let url: String?

    public init(
        id: String, name: String, type: String, capacityMiB: Int, freeMiB: Int,
        numVMsTotal: Int, numHostsConnected: Int, configStatus: EntityStatus = .green, url: String?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.capacityMiB = capacityMiB
        self.freeMiB = freeMiB
        self.numVMsTotal = numVMsTotal
        self.numHostsConnected = numHostsConnected
        self.configStatus = configStatus
        self.url = url
    }

    public var freePercent: Double {
        guard capacityMiB > 0 else { return 0 }
        return (Double(freeMiB) / Double(capacityMiB)) * 100
    }
}
