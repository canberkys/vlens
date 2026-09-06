import Foundation

/// Whether `ConnectionViewModel.checkSecurityAdvisories()` runs at all on
/// launch. Defaults to on — that's the feature's existing behavior from
/// before this toggle existed — but some privacy-conscious admins may not
/// want any outbound network call before they've connected to anything, so
/// Preferences exposes an opt-out. Same minimal `UserDefaults` shape as
/// `TutorialStore`.
// UserDefaults is internally thread-safe (per Apple's docs) but isn't
// marked Sendable in this SDK — @unchecked is a deliberate acknowledgment
// of that gap, not a real concurrency risk.
public struct SecurityAdvisoryPreferencesStore: @unchecked Sendable {
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
        static let enabled = "com.vlens.securityAdvisories.enabled"
    }
}
