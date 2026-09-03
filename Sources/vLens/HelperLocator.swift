import Foundation

/// Resolves where the `vlens-helper` binary lives. In the packaged app this
/// is a signed/notarized binary in Contents/Resources. During local
/// development (`swift run`) it isn't bundled yet, so fall back to the Go
/// module's own build output so `swift run` keeps working without a full
/// app-bundle step.
enum HelperLocator {
    static func resolve() -> URL {
        if let bundled = Bundle.main.url(forResource: "vlens-helper", withExtension: nil) {
            return bundled
        }
        if let envPath = ProcessInfo.processInfo.environment["VLENS_HELPER_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        // Dev fallback: Documents/Projects/vLens/helper/vlens-helper (built via `go build`)
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // vLens/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("helper/vlens-helper")
        return devPath
    }
}
