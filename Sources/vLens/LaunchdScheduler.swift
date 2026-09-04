import Foundation
import vLensCore

/// Turns an `AutomationSchedule` into a real `launchd` job — Faz 10B.
/// Shells out via `Process`, same pattern `VSphereHelperClient` already
/// uses for `vlens-helper`. Uses the modern `bootstrap`/`bootout` verbs
/// (not the deprecated `load`/`unload`).
enum LaunchdScheduler {
    static let label = "com.canberkki.vlens.scheduler"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/vlens-scheduler.log")
    }

    /// Writes the plist and loads it into the current user's launchd
    /// domain. Replaces any previously-installed job first (`bootout` is
    /// harmless — and expected to fail — when nothing is loaded yet).
    static func install(schedule: AutomationSchedule, profile: ConnectionProfile) throws {
        let cliPath = AutomationCLILocator.resolve().path
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            throw LaunchdSchedulerError.cliNotFound(cliPath)
        }

        var programArguments = [cliPath]
        switch schedule.action {
        case .snapshot(let fullDetail):
            programArguments += ["snapshot", "--profile", profile.name]
            if fullDetail { programArguments.append("--full-detail") }
        case .export(let tab, let format):
            let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            let outputPath = outputDir
                .appendingPathComponent("vLens-\(tab.rawValue)-scheduled.\(format.rawValue)").path
            programArguments += ["export", "--profile", profile.name, "--tab", tab.rawValue, "--format", format.rawValue, "--output", outputPath]
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            // launchd's Weekday is 0-6 (Sunday=0); AutomationSchedule stores
            // 1-7 (Sunday=1), matching Calendar/DateComponents indexing.
            "StartCalendarInterval": [
                "Weekday": schedule.weekday - 1,
                "Hour": schedule.hour,
                "Minute": schedule.minute
            ],
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path
        ]

        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        _ = try? runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    /// Tears down the launchd job and removes the plist — used when the
    /// user disables/removes automation from Preferences.
    static func uninstall() {
        _ = try? runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw LaunchdSchedulerError.launchctlFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

enum LaunchdSchedulerError: LocalizedError {
    case cliNotFound(String)
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let path):
            return "vlens-cli not found at \(path). A packaged .app build is needed for scheduled automation to work."
        case .launchctlFailed(let output):
            return "launchctl failed: \(output.isEmpty ? "unknown error" : output)"
        }
    }
}
