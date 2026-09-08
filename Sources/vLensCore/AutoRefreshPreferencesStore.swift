import Foundation

/// Whether `ConnectionViewModel` periodically re-runs `refresh()` on its
/// own, and how often — RVTools' own "auto refresh the data" preference
/// (found missing in the 2026-09-08 audit, verified against the real
/// RVTools PDF), vLens only had a manual Refresh button until now. Off by
/// default (a background poll against a real vCenter isn't something to
/// opt a user into silently) — same minimal `UserDefaults` shape as
/// `SecurityAdvisoryPreferencesStore`/`EndOfLifePreferencesStore`.
// UserDefaults is internally thread-safe (per Apple's docs) but isn't
// marked Sendable in this SDK — @unchecked is a deliberate acknowledgment
// of that gap, not a real concurrency risk.
public struct AutoRefreshPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled() -> Bool {
        defaults.object(forKey: Keys.enabled) as? Bool ?? false
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.enabled)
    }

    public func intervalMinutes() -> Int {
        let value = defaults.object(forKey: Keys.intervalMinutes) as? Int ?? 5
        return value > 0 ? value : 5
    }

    public func setIntervalMinutes(_ minutes: Int) {
        defaults.set(minutes, forKey: Keys.intervalMinutes)
    }

    private enum Keys {
        static let enabled = "com.vlens.autoRefresh.enabled"
        static let intervalMinutes = "com.vlens.autoRefresh.intervalMinutes"
    }
}
