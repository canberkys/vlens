import Foundation

/// Fetches ESXi's release lifecycle (general-support end-of-life per major
/// version) from endoflife.date's public API — deliberately not routed
/// through the Go helper: this has nothing to do with a vCenter connection,
/// just a plain HTTPS GET to a public, unauthenticated endpoint. Verified
/// with a real request during planning (GitHub issue #19), not assumed
/// from documentation alone — `GET https://endoflife.date/api/v1/products/esxi`
/// returns real `eolFrom`/`isEol`/`isMaintained` per major.minor release.
public struct EndOfLifeClient: Sendable {
    private static let endpoint = URL(string: "https://endoflife.date/api/v1/products/esxi")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchESXiReleaseCycles() async throws -> [ESXiReleaseCycle] {
        let (data, response) = try await session.data(from: Self.endpoint)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EndOfLifeClientError.badResponse
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.result.releases.map { raw in
            ESXiReleaseCycle(
                version: raw.name,
                eolDate: raw.eolFrom.flatMap { Self.dateFormatter.date(from: $0) },
                isEol: raw.isEol,
                isMaintained: raw.isMaintained
            )
        }
    }

    /// endoflife.date's dates are plain `yyyy-MM-dd`, no time component.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Wire format

    private struct APIResponse: Decodable {
        let result: ResultBody
        struct ResultBody: Decodable {
            let releases: [RawRelease]
        }
    }

    /// `eolFrom` is nullable in practice (a brand-new release endoflife.date
    /// hasn't assigned an EOL date to yet) — kept optional rather than
    /// assumed always present.
    private struct RawRelease: Decodable {
        let name: String
        let eolFrom: String?
        let isEol: Bool
        let isMaintained: Bool
    }
}

public enum EndOfLifeClientError: Error, Sendable {
    case badResponse
}
