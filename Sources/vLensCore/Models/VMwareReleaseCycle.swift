import Foundation

/// One VMware product's major.minor release cycle lifecycle info from
/// endoflife.date — not RVTools' concept, vLens' own idea (GitHub issue
/// #19): keep admins aware of an approaching or already-passed general-
/// support end-of-life without having to check endoflife.date manually.
/// Shared shape for both ESXi's and vCenter's own release cycles — both
/// products expose the identical schema on endoflife.date, and VMware
/// aligns their major.minor lifecycles anyway (see `EndOfLifeClient`).
/// Mirrors `SecurityAdvisory`/`VMSAClient`'s "quiet awareness, own toolbar
/// badge" pattern rather than folding into `HealthCheckEngine`, which
/// stays a pure, offline-data-only engine — same reasoning that kept VMSA
/// out of vHealth.
public struct VMwareReleaseCycle: Codable, Equatable, Sendable {
    /// Major.minor, e.g. "8.0" — matched against a collected version
    /// string's own major.minor prefix (patch-level differences don't
    /// change a release cycle's EOL date).
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

extension Array where Element == VMwareReleaseCycle {
    /// Matches a full version string (e.g. "8.0.3") against this list by
    /// major.minor prefix (e.g. "8.0").
    public func matching(version: String) -> VMwareReleaseCycle? {
        let components = version.split(separator: ".")
        guard components.count >= 2 else { return nil }
        let majorMinor = "\(components[0]).\(components[1])"
        return first { $0.version == majorMinor }
    }
}

/// Red: general support has already ended. Orange: ending within
/// `warningDays` (default 180 — a VMware upgrade across a cluster
/// realistically takes months to plan, test, and execute, so a shorter
/// window wouldn't give much real runway). Green: otherwise, including a
/// version endoflife.date has no EOL date for yet.
public enum EOLSeverity: Sendable {
    case red, orange, green
}

func eolSeverity(for cycle: VMwareReleaseCycle, warningDays: Int = 180) -> EOLSeverity {
    guard let eolDate = cycle.eolDate else { return .green }
    if cycle.isEol || eolDate < Date() { return .red }
    let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: eolDate).day ?? Int.max
    return daysUntil <= warningDays ? .orange : .green
}

/// One real, currently-connected (or demo) host paired with whatever
/// release-cycle lifecycle data matched its `esxVersion` — the actual
/// thing `VMwareEOLView` displays.
public struct HostEOLStatus: Identifiable, Sendable {
    public var id: String { hostName }
    public let hostName: String
    public let esxVersion: String
    public let cycle: VMwareReleaseCycle

    public init(hostName: String, esxVersion: String, cycle: VMwareReleaseCycle) {
        self.hostName = hostName
        self.esxVersion = esxVersion
        self.cycle = cycle
    }

    public func severity(warningDays: Int = 180) -> EOLSeverity {
        eolSeverity(for: cycle, warningDays: warningDays)
    }
}

/// Same idea as `HostEOLStatus`, for the single connected vCenter itself
/// rather than a host — there's only ever one per connection, so this
/// stays a single optional value (`ConnectionViewModel.vCenterEOLStatus`)
/// rather than a list. Deliberately NOT its own sidebar tab: a tab that
/// always shows exactly one row doesn't fit this app's "one row per real
/// inventory item" pattern the way every other tab does — it's shown as
/// an extra row in the same toolbar popover as the hosts instead.
public struct VCenterEOLStatus: Identifiable, Sendable {
    public var id: String { "vcenter" }
    public let version: String
    public let cycle: VMwareReleaseCycle

    public init(version: String, cycle: VMwareReleaseCycle) {
        self.version = version
        self.cycle = cycle
    }

    public func severity(warningDays: Int = 180) -> EOLSeverity {
        eolSeverity(for: cycle, warningDays: warningDays)
    }
}
