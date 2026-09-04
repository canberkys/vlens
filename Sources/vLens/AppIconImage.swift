import AppKit
import SwiftUI

/// The real app icon, usable as SwiftUI content (Connect screen branding,
/// About window) — not `NSImage(named: "AppIcon")`, which only resolves in
/// a packaged `.app` with a real Info.plist; `swift run` has neither, same
/// reasoning as `AppVersion`/`HelperLocator`'s dev/bundle fallback pattern.
/// Bundled as a plain SwiftPM resource (`Bundle.module`) rather than an
/// asset catalog so it loads identically in both dev and packaged builds.
enum AppIconImage {
    static var image: Image {
        guard let url = AppResourceLocator.resourceBundle().url(forResource: "AppIconImage", withExtension: "png"),
            let nsImage = NSImage(contentsOf: url)
        else {
            return Image(systemName: "server.rack")
        }
        return Image(nsImage: nsImage)
    }
}
