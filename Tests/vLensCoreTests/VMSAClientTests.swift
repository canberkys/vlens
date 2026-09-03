import Foundation
import Testing
@testable import vLensCore

/// Stubs the HTTP layer so this test exercises the real request/decode path
/// without hitting the network — the fixture JSON below is a real response
/// captured from Broadcom's endpoint during development, not invented.
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

private func makeStubbedClient(json: String, statusCode: Int = 200) -> VMSAClient {
    StubURLProtocol.responseData = Data(json.utf8)
    StubURLProtocol.statusCode = statusCode
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return VMSAClient(session: URLSession(configuration: config))
}

// StubURLProtocol's response is shared mutable static state (Foundation's
// URLProtocol registration is inherently class-based, no per-instance hook
// for injecting a mock response) — .serialized forces these to run one at a
// time so Swift Testing's default parallel execution can't race them.
@Suite(.serialized)
struct VMSAClientTests {

@Test func decodesRealCapturedResponseShape() async throws {
    // Captured verbatim from a live request during planning (see
    // docs/vLens-Reference.md §11's VMSA note) — not a guessed schema.
    let json = """
    {"success":true,"data":{"list":[{"affectedCve":"CVE-2026-59346, CVE-2026-59347","alertType":"S","documentId":"VCDSA38288","notificationId":38288,"notificationUrl":"https://support.broadcom.com/web/ecx/support-content-notification/-/external/content/SecurityAdvisories/0/38288","published":"03 September 2026","severity":"CRITICAL","status":"OPEN","supportProducts":"VMware Fusion,VMware Work...","title":"VMSA-2026-0007: VMware Workstation and Fusion updates address integer-overflow and buffer overflow vulnerabilities (CVE-2026-59346, CVE-2026-59347)","totalRecords":null,"updated":"2026-09-03T08:58:26.960422","workAround":"None"}],"pageInfo":{"totalCount":341,"currentPage":0,"sortBy":"UNSORTED","pageSize":2,"nextPage":1,"lastPage":170,"firstPage":0}},"correlationId":"e922aef2-1cb7-4c88-8368-c688059c66d6"}
    """
    let client = makeStubbedClient(json: json)

    let advisories = try await client.fetchRecentAdvisories()

    #expect(advisories.count == 1)
    let advisory = advisories[0]
    #expect(advisory.id == 38288)
    #expect(advisory.documentId == "VCDSA38288")
    #expect(advisory.severity == "CRITICAL")
    #expect(advisory.isNotable)
    #expect(advisory.cves == ["CVE-2026-59346", "CVE-2026-59347"])
    #expect(advisory.url.hasPrefix("https://support.broadcom.com"))
    #expect(advisory.publishedDate != nil)
}

@Test func mediumSeverityIsNotNotable() async throws {
    let json = """
    {"success":true,"data":{"list":[{"affectedCve":"","alertType":"S","documentId":"D1","notificationId":1,"notificationUrl":"https://example.com","published":"01 January 2026","severity":"MEDIUM","status":"OPEN","supportProducts":"VMware ESXi","title":"Test advisory","totalRecords":null,"updated":"2026-01-01T00:00:00","workAround":"None"}]},"pageInfo":{}}
    """
    let client = makeStubbedClient(json: json)

    let advisories = try await client.fetchRecentAdvisories()

    #expect(advisories[0].isNotable == false)
    #expect(advisories[0].cves.isEmpty)
}

@Test func apiReportedFailureThrows() async {
    let json = """
    {"success":false,"data":{"list":[]}}
    """
    let client = makeStubbedClient(json: json)

    await #expect(throws: VMSAClientError.self) {
        try await client.fetchRecentAdvisories()
    }
}

@Test func badHTTPStatusThrows() async {
    let client = makeStubbedClient(json: "{}", statusCode: 500)

    await #expect(throws: VMSAClientError.self) {
        try await client.fetchRecentAdvisories()
    }
}

}
