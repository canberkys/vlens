import Foundation
import Testing
@testable import vLensCore

@Test func decodesVMPerformanceInfoFromHelperJSON() throws {
    let json = """
    {"id":"abc-123","vmName":"web-01","intervalMinutes":60,"collectedAt":"2026-09-03T17:54:06Z","avgCpuUsagePercent":7.44,"maxCpuUsagePercent":34.96,"avgRamUsagePercent":31.72,"maxRamUsagePercent":52.2,"maxReadIOSizeBytes":null,"maxWriteIOSizeBytes":null}
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601 // matches VSphereHelperClient's decoder config
    let perf = try decoder.decode(VMPerformanceInfo.self, from: json)

    #expect(perf.vmName == "web-01")
    #expect(perf.intervalMinutes == 60)
    #expect(perf.avgCpuUsagePercent == 7.44)
    #expect(perf.maxReadIOSizeBytes == nil)
}
