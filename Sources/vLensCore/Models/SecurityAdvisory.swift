import Foundation

/// One VMware/Broadcom security advisory (VMSA) — not RVTools' concept,
/// vLens' own idea for keeping admins aware of published advisories without
/// them having to check the Broadcom support portal manually. See
/// `VMSAClient` for where this comes from.
public struct SecurityAdvisory: Codable, Identifiable, Sendable {
    public let id: Int
    public let documentId: String
    public let title: String
    /// Raw value from the API (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW` observed) —
    /// kept as a string rather than a strict enum since this is an external,
    /// unversioned API not under vLens' control; an unrecognized future value
    /// should degrade gracefully in the UI, not fail to decode.
    public let severity: String
    public let status: String
    public let publishedDate: Date?
    public let cves: [String]
    /// Comma-separated product names as the API returns them — sometimes
    /// truncated with "..." by Broadcom's own backend (observed, not a bug
    /// on vLens' side), kept as-is rather than guessing at the full list.
    public let affectedProducts: String
    public let url: String

    public init(
        id: Int, documentId: String, title: String, severity: String, status: String,
        publishedDate: Date?, cves: [String], affectedProducts: String, url: String
    ) {
        self.id = id
        self.documentId = documentId
        self.title = title
        self.severity = severity
        self.status = status
        self.publishedDate = publishedDate
        self.cves = cves
        self.affectedProducts = affectedProducts
        self.url = url
    }

    /// `true` for the severities worth surfacing a badge for — deliberately
    /// excludes MEDIUM/LOW so the toolbar indicator stays meaningful (a badge
    /// that's always non-zero is noise, not signal).
    public var isNotable: Bool {
        severity == "CRITICAL" || severity == "HIGH"
    }
}
