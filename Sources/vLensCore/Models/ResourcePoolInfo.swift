import Foundation

/// RVTools vRP tab — resource pools (rvtools.txt ~line 2682).
public struct ResourcePoolInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let ownerName: String?
    public let cpuReservationMHz: Int
    public let cpuLimitMHz: Int // -1 == no limit
    public let memoryReservationMiB: Int
    public let memoryLimitMiB: Int // -1 == no limit
    public let numVMs: Int

    public init(
        id: String, name: String, ownerName: String?, cpuReservationMHz: Int, cpuLimitMHz: Int,
        memoryReservationMiB: Int, memoryLimitMiB: Int, numVMs: Int
    ) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.cpuReservationMHz = cpuReservationMHz
        self.cpuLimitMHz = cpuLimitMHz
        self.memoryReservationMiB = memoryReservationMiB
        self.memoryLimitMiB = memoryLimitMiB
        self.numVMs = numVMs
    }
}
