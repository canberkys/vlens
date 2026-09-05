import Foundation
import Testing
@testable import vLensCore

/// Same stub pattern as VMSAClientTests — no network hit, real fixture data.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubbedClient(json: String, statusCode: Int = 200) -> EndOfLifeClient {
    StubURLProtocol.responseData = Data(json.utf8)
    StubURLProtocol.statusCode = statusCode
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return EndOfLifeClient(session: URLSession(configuration: config))
}

@Suite(.serialized)
struct EndOfLifeClientTests {

    // A real, trimmed subset of a live response captured from
    // endoflife.date's /api/v1/products/esxi during planning (GitHub issue
    // #19) — not a guessed schema. 8.0 is currently supported, 7.0's
    // general support really did end 2025-10-02.
    private static let capturedJSON = """
    {"result": {"releases": [{"name": "8.0", "eolFrom": "2027-10-11", "isEol": false, "isMaintained": true}, {"name": "7.0", "eolFrom": "2025-10-02", "isEol": true, "isMaintained": false}]}}
    """

    @Test func decodesRealCapturedResponseShape() async throws {
        let client = makeStubbedClient(json: Self.capturedJSON)

        let cycles = try await client.fetchESXiReleaseCycles()

        #expect(cycles.count == 2)
        let eight = try #require(cycles.first { $0.version == "8.0" })
        #expect(eight.isEol == false)
        #expect(eight.isMaintained == true)
        let seven = try #require(cycles.first { $0.version == "7.0" })
        #expect(seven.isEol == true)
        #expect(seven.isMaintained == false)
    }

    @Test func badHTTPStatusThrows() async throws {
        let client = makeStubbedClient(json: "", statusCode: 500)
        await #expect(throws: (any Error).self) {
            _ = try await client.fetchESXiReleaseCycles()
        }
    }

    /// Same decode path, different endoflife.date product (vCenter is a
    /// separate product from ESXi, but shares the identical schema —
    /// confirmed with a real request during planning, GitHub issue #19).
    @Test func fetchVCenterReleaseCyclesUsesSameDecodePath() async throws {
        let client = makeStubbedClient(json: Self.capturedJSON)

        let cycles = try await client.fetchVCenterReleaseCycles()

        #expect(cycles.count == 2)
        #expect(cycles.contains { $0.version == "8.0" && !$0.isEol })
    }
}

@Suite
struct VMwareReleaseCycleMatchingTests {
    private static let cycles = [
        VMwareReleaseCycle(version: "8.0", eolDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()), isEol: false, isMaintained: true),
        VMwareReleaseCycle(version: "7.0", eolDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()), isEol: true, isMaintained: false),
    ]

    @Test func matchesByMajorMinorIgnoringPatchVersion() {
        let match = Self.cycles.matching(version: "7.0.3")
        #expect(match?.version == "7.0")
    }

    @Test func returnsNilForUnknownVersion() {
        #expect(Self.cycles.matching(version: "9.9.9") == nil)
    }

    @Test func returnsNilForMalformedVersionString() {
        #expect(Self.cycles.matching(version: "notaversion") == nil)
    }

    @Test func severityIsRedWhenAlreadyEol() {
        let status = HostEOLStatus(hostName: "esx-01", esxVersion: "7.0.3", cycle: Self.cycles[1])
        #expect(status.severity() == .red)
    }

    @Test func severityIsGreenWhenFarFromEol() {
        let status = HostEOLStatus(hostName: "esx-02", esxVersion: "8.0.3", cycle: Self.cycles[0])
        #expect(status.severity() == .green)
    }

    @Test func severityIsOrangeWithinWarningWindow() {
        let soonCycle = VMwareReleaseCycle(
            version: "8.0", eolDate: Calendar.current.date(byAdding: .day, value: 60, to: Date()),
            isEol: false, isMaintained: true
        )
        let status = HostEOLStatus(hostName: "esx-03", esxVersion: "8.0.3", cycle: soonCycle)
        #expect(status.severity(warningDays: 180) == .orange)
    }

    @Test func severityIsGreenWhenNoEolDateIsKnownYet() {
        let unknownCycle = VMwareReleaseCycle(version: "9.1", eolDate: nil, isEol: false, isMaintained: true)
        let status = HostEOLStatus(hostName: "esx-04", esxVersion: "9.1.0", cycle: unknownCycle)
        #expect(status.severity() == .green)
    }

    /// vCenter shares the exact same severity logic as a host — same
    /// underlying `eolSeverity(for:warningDays:)`, just a different wrapper
    /// type since there's only ever one vCenter per connection.
    @Test func vCenterStatusSeverityIsRedWhenAlreadyEol() {
        let status = VCenterEOLStatus(version: "7.0.3", cycle: Self.cycles[1])
        #expect(status.severity() == .red)
    }
}
