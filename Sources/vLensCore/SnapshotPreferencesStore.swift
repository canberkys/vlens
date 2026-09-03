import Foundation

/// Which `SnapshotMetricDescriptor` rows show in the Snapshots tab's
/// Compare panel — user-configurable in Preferences. Same UserDefaults
/// pattern as `HealthCheckPreferencesStore`. Every metric is still always
/// *captured* (they're cheap scalars, no reason to make capture
/// conditional) — this only controls what's *displayed*.
public struct SnapshotPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadEnabledMetricKeys() -> Set<String> {
        guard let saved = defaults.array(forKey: Keys.enabledMetrics) as? [String] else {
            return Set(SnapshotMetricDescriptor.all.map(\.key)) // default: everything on
        }
        return Set(saved)
    }

    public func save(enabledMetricKeys: Set<String>) {
        defaults.set(Array(enabledMetricKeys), forKey: Keys.enabledMetrics)
    }

    private enum Keys {
        static let enabledMetrics = "com.vlens.snapshot.enabledMetricKeys"
    }
}
