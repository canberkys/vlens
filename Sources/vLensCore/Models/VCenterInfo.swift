import Foundation

/// vCenter's own `AboutInfo` — free to collect (populated during login
/// itself, no extra round trip). Backs the executive report's header
/// (`ReportView`) — not shown as its own tab.
public struct VCenterInfo: Codable, Sendable {
    public let fullName: String
    public let version: String
    public let build: String
    public let apiVersion: String

    public init(fullName: String, version: String, build: String, apiVersion: String) {
        self.fullName = fullName
        self.version = version
        self.build = build
        self.apiVersion = apiVersion
    }
}
