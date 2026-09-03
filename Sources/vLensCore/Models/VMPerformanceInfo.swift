import Foundation

/// Not an RVTools tab — RVTools' quickStats-based columns (see vCPU/vMemory)
/// only ever show an instantaneous value. This is historical, sampled over a
/// user-chosen time window via vCenter's `PerformanceManager`, collected by
/// its own helper action (`collectPerformance`) deliberately kept out of
/// `collectAll` — see `mapVMNetworks`'s sibling `collectPerformance` in
/// `helper/main.go` for why. Every metric is optional: vCenter (or a
/// simulator like vcsim) not reporting a counter is a real, distinct state
/// from "the value is zero," and this app doesn't paper over that gap.
public struct VMPerformanceInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let vmName: String
    public let intervalMinutes: Int
    public let collectedAt: Date
    public let avgCpuUsagePercent: Double?
    public let maxCpuUsagePercent: Double?
    public let avgRamUsagePercent: Double?
    public let maxRamUsagePercent: Double?
    public let maxReadIOSizeBytes: Int64?
    public let maxWriteIOSizeBytes: Int64?

    public init(
        id: String, vmName: String, intervalMinutes: Int, collectedAt: Date,
        avgCpuUsagePercent: Double?, maxCpuUsagePercent: Double?,
        avgRamUsagePercent: Double?, maxRamUsagePercent: Double?,
        maxReadIOSizeBytes: Int64?, maxWriteIOSizeBytes: Int64?
    ) {
        self.id = id
        self.vmName = vmName
        self.intervalMinutes = intervalMinutes
        self.collectedAt = collectedAt
        self.avgCpuUsagePercent = avgCpuUsagePercent
        self.maxCpuUsagePercent = maxCpuUsagePercent
        self.avgRamUsagePercent = avgRamUsagePercent
        self.maxRamUsagePercent = maxRamUsagePercent
        self.maxReadIOSizeBytes = maxReadIOSizeBytes
        self.maxWriteIOSizeBytes = maxWriteIOSizeBytes
    }
}
