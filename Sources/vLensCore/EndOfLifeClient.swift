import Foundation

/// Fetches VMware product release lifecycle (general-support end-of-life
/// per major version) from endoflife.date's public API — deliberately not
/// routed through the Go helper: this has nothing to do with a vCenter
/// connection, just a plain HTTPS GET to a public, unauthenticated
/// endpoint. Both ESXi and vCenter are separate products on endoflife.date
/// (`/api/v1/products/esxi`, `/api/v1/products/vcenter`) but share the
/// identical response schema — verified with real requests during
/// planning (GitHub issue #19), not assumed from documentation alone.
public struct EndOfLifeClient: Sendable {
    private static let baseURL = URL(string: "https://endoflife.date/api/v1/products/")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchESXiReleaseCycles() async throws -> [VMwareReleaseCycle] {
        try await fetchReleaseCycles(product: "esxi")
    }

    public func fetchVCenterReleaseCycles() async throws -> [VMwareReleaseCycle] {
        try await fetchReleaseCycles(product: "vcenter")
    }

    private func fetchReleaseCycles(product: String) async throws -> [VMwareReleaseCycle] {
        let url = Self.baseURL.appendingPathComponent(product)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EndOfLifeClientError.badResponse
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.result.releases.map { raw in
            VMwareReleaseCycle(
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
