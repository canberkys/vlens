import Foundation

/// Tracks which one-time tutorials/coachmarks have already been shown — the
/// first-run welcome overlay and per-feature "here's what this does"
/// popovers. Same UserDefaults pattern as `HealthCheckPreferencesStore`/
/// `SnapshotPreferencesStore`. IDs are freeform strings (e.g.
/// `"onboarding.welcome"`, `"tutorial.snapshots"`) so a new feature just
/// picks a new ID — no registry to update.
public struct TutorialStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasSeen(_ id: String) -> Bool {
        defaults.bool(forKey: key(for: id))
    }

    public func markSeen(_ id: String) {
        defaults.set(true, forKey: key(for: id))
    }

    /// Backs Preferences' "Reset tutorials" button — lets a user
    /// deliberately see them again, without them ever reappearing on their own.
    public func resetAll(ids: [String]) {
        for id in ids {
            defaults.removeObject(forKey: key(for: id))
        }
    }

    private func key(for id: String) -> String { "com.vlens.tutorial.\(id)" }
}
