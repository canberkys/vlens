import Foundation

/// Reads version info from the real packaged app's Info.plist when running
/// as a proper `.app` bundle; falls back to the same values hardcoded in
/// `Resources/Info.plist` when running via `swift run` in development
/// (Bundle.main has no real Info.plist then) — same "bundle lookup, then dev
/// fallback" shape as `HelperLocator.resolve()`.
enum AppVersion {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.3"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "6"
    }
}
