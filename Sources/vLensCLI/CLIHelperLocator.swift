import Foundation

/// Resolves `vlens-helper` for the CLI target — mirrors
/// `Sources/vLens/HelperLocator.swift`'s fallback chain, but can't use
/// `Bundle.main.url(forResource:)` since `vlens-cli` is a bare Mach-O
/// executable, not a proper bundle. In the packaged app it sits at
/// `vLens.app/Contents/MacOS/vlens-cli`, so the helper is found by walking
/// up from the running executable's own path instead.
enum CLIHelperLocator {
    static func resolve() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["VLENS_HELPER_PATH"] {
            return URL(fileURLWithPath: envPath)
        }

        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = exeURL
            .deletingLastPathComponent() // Contents/MacOS/
            .deletingLastPathComponent() // Contents/
            .appendingPathComponent("Resources/vlens-helper")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        // Dev fallback: repo's helper/vlens-helper (built via `go build`),
        // same convention as HelperLocator.swift's #filePath walk-up.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // vLensCLI/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("helper/vlens-helper")
    }
}
