import Foundation

/// Whether `ConnectionViewModel.checkVMwareEndOfLife()` runs at all on
/// connect. Defaults to on, same reasoning as `SecurityAdvisoryPreferencesStore`
/// (which this mirrors exactly) — both are plain, independent internet
/// requests some privacy-conscious admins may want to opt out of before
/// they've connected to anything.
// UserDefaults is internally thread-safe (per Apple's docs) but isn't
// marked Sendable in this SDK — @unchecked is a deliberate acknowledgment
// of that gap, not a real concurrency risk.
public struct EndOfLifePreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled() -> Bool {
        defaults.object(forKey: Keys.enabled) as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.enabled)
    }

    private enum Keys {
        static let enabled = "com.vlens.endOfLife.enabled"
    }
}
