import Foundation

/// vCenter's own `AboutInfo` — free to collect (populated during login
/// itself, no extra round trip). Backs both the executive report's header
/// (`ReportView`) and the vSource tab (`VSourceTabView`) — RVTools' own
/// tab for the connected SDK/vCenter server's identity, found missing in
/// the 2026-09-08 audit (RVTools' PDF index lists 26 real tabs, not 24 —
/// 24 is the vHealth rule count, this app's own docs used to conflate the
/// two). A merged multi-vCenter export naturally produces one row per
/// source, which is what makes this a real tab rather than the
/// always-exactly-one-row case `VCenterEOLStatus` deliberately avoided
/// being (see that type's own doc comment).
public struct VCenterInfo: Codable, Identifiable, Sendable {
    public var id: String { instanceUUID ?? fullName }

    public let name: String
    public let fullName: String
    public let vendor: String
    public let version: String
    public let patchLevel: String?
    public let build: String
    public let osType: String
    public let apiType: String
    public let apiVersion: String
    public let instanceUUID: String?

    public init(
        name: String, fullName: String, vendor: String, version: String, patchLevel: String?,
        build: String, osType: String, apiType: String, apiVersion: String, instanceUUID: String?
    ) {
        self.name = name
        self.fullName = fullName
        self.vendor = vendor
        self.version = version
        self.patchLevel = patchLevel
        self.build = build
        self.osType = osType
        self.apiType = apiType
        self.apiVersion = apiVersion
        self.instanceUUID = instanceUUID
    }
}
