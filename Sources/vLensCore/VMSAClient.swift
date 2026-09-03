import Foundation

/// Fetches recent VMware security advisories from Broadcom's own JSON API —
/// deliberately not routed through the Go helper: this has nothing to do
/// with a vCenter connection, just a plain HTTPS GET/POST to a public
/// endpoint. Endpoint verified with a real request during planning, not
/// assumed from documentation alone — the officially-documented GET URL
/// (`knowledge.broadcom.com/external/article/408302`) 404s in practice; this
/// POST endpoint (also referenced in that same documentation ecosystem, and
/// independently confirmed by community write-ups) is the one that actually
/// works, no auth required.
public struct VMSAClient: Sendable {
    private static let endpoint = URL(string: "https://support.broadcom.com/web/ecx/security-advisory/-/securityadvisory/getSecurityAdvisoryList")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// - Parameter segment: Broadcom's product-line filter. "VC" was
    ///   verified to return the full VMware-by-Broadcom family relevant to
    ///   vSphere admins (ESX, vCenter, Cloud Foundation, Workstation,
    ///   Fusion, Aria Operations) — not narrowly VCF-only despite some
    ///   documentation implying that.
    public func fetchRecentAdvisories(pageSize: Int = 20, segment: String = "VC") async throws -> [SecurityAdvisory] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(pageNumber: 0, pageSize: pageSize, searchVal: "", segment: segment, sortInfo: .init(column: "", order: ""))
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VMSAClientError.badResponse
        }

        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        guard decoded.success else {
            throw VMSAClientError.apiReportedFailure
        }
        return decoded.data.list.map(Self.mapAdvisory)
    }

    private static func mapAdvisory(_ raw: RawAdvisory) -> SecurityAdvisory {
        SecurityAdvisory(
            id: raw.notificationId,
            documentId: raw.documentId,
            title: raw.title,
            severity: raw.severity,
            status: raw.status,
            publishedDate: publishedDateFormatter.date(from: raw.published),
            cves: raw.affectedCve.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            affectedProducts: raw.supportProducts,
            url: raw.notificationUrl
        )
    }

    /// The API returns publish dates as e.g. "03 September 2026" — not
    /// ISO8601. Locale pinned to en_US_POSIX so parsing month names doesn't
    /// depend on the system locale.
    private static let publishedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMMM yyyy"
        return formatter
    }()

    // MARK: - Wire format

    private struct RequestBody: Encodable {
        let pageNumber: Int
        let pageSize: Int
        let searchVal: String
        let segment: String
        let sortInfo: SortInfo
        struct SortInfo: Encodable { let column: String; let order: String }
    }

    private struct ListResponse: Decodable {
        let success: Bool
        let data: ListData
    }

    private struct ListData: Decodable {
        let list: [RawAdvisory]
    }

    private struct RawAdvisory: Decodable {
        let documentId: String
        let notificationId: Int
        let notificationUrl: String
        let published: String
        let severity: String
        let status: String
        let supportProducts: String
        let title: String
        let affectedCve: String
    }
}

public enum VMSAClientError: Error, Sendable {
    case badResponse
    case apiReportedFailure
}
