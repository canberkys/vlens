import Foundation

/// One ESXi major.minor release cycle's lifecycle info from endoflife.date
/// — not RVTools' concept, vLens' own idea (GitHub issue #19): keep admins
/// aware of an approaching or already-passed ESXi general-support
/// end-of-life without having to check endoflife.date manually. Mirrors
/// `SecurityAdvisory`/`VMSAClient`'s "quiet awareness, own toolbar badge"
/// pattern rather than folding into `HealthCheckEngine`, which stays a
/// pure, offline-data-only engine — same reasoning that kept VMSA out of
/// vHealth.
public struct ESXiReleaseCycle: Codable, Equatable, Sendable {
    /// Major.minor, e.g. "8.0" — matched against `HostInfo.esxVersion`'s
    /// own major.minor prefix (patch-level differences don't change a
    /// release cycle's EOL date).
    public let version: String
    public let eolDate: Date?
    public let isEol: Bool
    public let isMaintained: Bool

    public init(version: String, eolDate: Date?, isEol: Bool, isMaintained: Bool) {
        self.version = version
        self.eolDate = eolDate
        self.isEol = isEol
        self.isMaintained = isMaintained
    }
}

extension Array where Element == ESXiReleaseCycle {
    /// Matches a full ESXi version string (e.g. "8.0.3") against this list
    /// by major.minor prefix (e.g. "8.0").
    public func matching(esxVersion: String) -> ESXiReleaseCycle? {
        let components = esxVersion.split(separator: ".")
        guard components.count >= 2 else { return nil }
        let majorMinor = "\(components[0]).\(components[1])"
        return first { $0.version == majorMinor }
    }
}

/// One real, currently-connected (or demo) host paired with whatever
/// release-cycle lifecycle data matched its `esxVersion` — the actual
/// thing `ESXiEOLView` displays.
public struct HostEOLStatus: Identifiable, Sendable {
    public var id: String { hostName }
    public let hostName: String
    public let esxVersion: String
    public let cycle: ESXiReleaseCycle

    public init(hostName: String, esxVersion: String, cycle: ESXiReleaseCycle) {
        self.hostName = hostName
        self.esxVersion = esxVersion
        self.cycle = cycle
    }

    public enum Severity: Sendable {
        case red, orange, green
    }

    /// Red: general support has already ended. Orange: ending within
    /// `warningDays` (default 180 — an ESXi upgrade across a cluster
    /// realistically takes months to plan, test, and execute, so a
    /// shorter window wouldn't give much real runway). Green: otherwise,
    /// including a version endoflife.date has no EOL date for yet.
    public func severity(warningDays: Int = 180) -> Severity {
        guard let eolDate = cycle.eolDate else { return .green }
        if cycle.isEol || eolDate < Date() { return .red }
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: eolDate).day ?? Int.max
        return daysUntil <= warningDays ? .orange : .green
    }
}
