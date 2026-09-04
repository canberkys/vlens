import Foundation

/// What `vlens-cli` should run and when — Preferences' "Automation" section
/// (Faz 10B) writes this, `LaunchdScheduler` (app layer, Process-based —
/// same shape as `VSphereHelperClient`) turns it into a launchd plist.
///
/// v1 supports exactly one active schedule, not a list — the concrete use
/// case that motivated this ("her Pazartesi 09:00'da bir snapshot al") was
/// itself singular, and a list adds real complexity (multiple launchd
/// labels, a schedule-management UI) for a need that hasn't come up yet.
public struct AutomationSchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var profileID: UUID
    public var action: AutomationAction
    /// 1 = Sunday ... 7 = Saturday — matches `DateComponents.weekday` /
    /// `Calendar.current.weekdaySymbols` indexing, so the Preferences
    /// picker can use `Calendar` directly. `LaunchdScheduler` converts to
    /// launchd's own 0-6 (Sunday=0) convention when writing the plist.
    public var weekday: Int
    public var hour: Int
    public var minute: Int

    public init(enabled: Bool = false, profileID: UUID, action: AutomationAction, weekday: Int, hour: Int, minute: Int) {
        self.enabled = enabled
        self.profileID = profileID
        self.action = action
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

public enum AutomationAction: Codable, Equatable, Sendable {
    case snapshot(fullDetail: Bool)
    case export(tab: ExportTab, format: ExportFormat)
}

/// UserDefaults-backed, same pattern as every other `*PreferencesStore` in
/// this file set (`SnapshotPreferencesStore`, `HealthCheckPreferencesStore`).
public struct AutomationPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AutomationSchedule? {
        guard let data = defaults.data(forKey: Keys.schedule) else { return nil }
        return try? JSONDecoder().decode(AutomationSchedule.self, from: data)
    }

    /// `nil` clears the stored schedule (used when the user disables/removes
    /// automation) — callers are also responsible for tearing down the
    /// actual launchd job via `LaunchdScheduler.uninstall()`, this only
    /// touches the persisted preference.
    public func save(_ schedule: AutomationSchedule?) {
        guard let schedule else {
            defaults.removeObject(forKey: Keys.schedule)
            return
        }
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: Keys.schedule)
    }

    private enum Keys {
        static let schedule = "com.vlens.automation.schedule"
    }
}
