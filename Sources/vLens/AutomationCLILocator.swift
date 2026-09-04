import Foundation

/// Resolves `vlens-cli` for the GUI app to hand to launchd — same
/// resolution shape as `HelperLocator.resolve()`. In the packaged app this
/// is a signed binary at `Contents/MacOS/vlens-cli` (a sibling of `vLens`
/// itself, not a `Resources` item like `vlens-helper` — it's a real
/// executable target, not a bundled tool). In dev (`swift run vLens`),
/// there's no such bundle layout, so this falls back to the SwiftPM build
/// output next to the current binary.
enum AutomationCLILocator {
    static func resolve() -> URL {
        let bundled = URL(fileURLWithPath: Bundle.main.bundlePath)
            .appendingPathComponent("Contents/MacOS/vlens-cli")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        if let envPath = ProcessInfo.processInfo.environment["VLENS_CLI_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        // Dev fallback: SwiftPM's own build output, alongside `vLens`
        // itself — `Bundle.main.executableURL` points at `.build/<config>/vLens`
        // when running via `swift run`.
        if let exeURL = Bundle.main.executableURL {
            let devPath = exeURL.deletingLastPathComponent().appendingPathComponent("vlens-cli")
            if FileManager.default.isExecutableFile(atPath: devPath.path) {
                return devPath
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // vLens/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // project root
            .appendingPathComponent(".build/debug/vlens-cli")
    }
}
