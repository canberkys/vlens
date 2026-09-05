import Foundation

/// Persists the user-adjustable vHealth thresholds — RVTools' equivalent is
/// its Health Properties panel. `UserDefaults` rather than a JSON file: this
/// is exactly the kind of small, simple, single-window preference set
/// `UserDefaults` exists for, unlike `ConnectionProfileStore`'s list of
/// records or `LocalJSONCertificateTrustStore`'s security-sensitive data.
// UserDefaults is internally thread-safe (per Apple's docs) but isn't
// marked Sendable in this SDK — @unchecked is a deliberate acknowledgment
// of that gap, not a real concurrency risk.
public struct HealthCheckPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HealthCheckThresholds {
        let fallback = HealthCheckThresholds()
        let datastoreFreeSpacePercent = defaults.object(forKey: Keys.datastoreFreeSpacePercent) as? Double
        let vCPUsPerCoreWarning = defaults.object(forKey: Keys.vCPUsPerCoreWarning) as? Double
        let guestDiskFreeSpacePercent = defaults.object(forKey: Keys.guestDiskFreeSpacePercent) as? Double
        let maxVMsPerDatastore = defaults.object(forKey: Keys.maxVMsPerDatastore) as? Int
        let certificateExpiryWarningDays = defaults.object(forKey: Keys.certificateExpiryWarningDays) as? Int
        return HealthCheckThresholds(
            datastoreFreeSpacePercent: datastoreFreeSpacePercent ?? fallback.datastoreFreeSpacePercent,
            vCPUsPerCoreWarning: vCPUsPerCoreWarning ?? fallback.vCPUsPerCoreWarning,
            guestDiskFreeSpacePercent: guestDiskFreeSpacePercent ?? fallback.guestDiskFreeSpacePercent,
            maxVMsPerDatastore: maxVMsPerDatastore ?? fallback.maxVMsPerDatastore,
            certificateExpiryWarningDays: certificateExpiryWarningDays ?? fallback.certificateExpiryWarningDays
        )
    }

    public func save(_ thresholds: HealthCheckThresholds) {
        defaults.set(thresholds.datastoreFreeSpacePercent, forKey: Keys.datastoreFreeSpacePercent)
        defaults.set(thresholds.vCPUsPerCoreWarning, forKey: Keys.vCPUsPerCoreWarning)
        defaults.set(thresholds.guestDiskFreeSpacePercent, forKey: Keys.guestDiskFreeSpacePercent)
        defaults.set(thresholds.maxVMsPerDatastore, forKey: Keys.maxVMsPerDatastore)
        defaults.set(thresholds.certificateExpiryWarningDays, forKey: Keys.certificateExpiryWarningDays)
    }

    private enum Keys {
        static let datastoreFreeSpacePercent = "com.vlens.healthCheck.datastoreFreeSpacePercent"
        static let vCPUsPerCoreWarning = "com.vlens.healthCheck.vCPUsPerCoreWarning"
        static let guestDiskFreeSpacePercent = "com.vlens.healthCheck.guestDiskFreeSpacePercent"
        static let maxVMsPerDatastore = "com.vlens.healthCheck.maxVMsPerDatastore"
        static let certificateExpiryWarningDays = "com.vlens.healthCheck.certificateExpiryWarningDays"
    }
}
