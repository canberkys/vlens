import Foundation

/// Locates the SwiftPM resource bundle declared in `Package.swift`
/// (`AppIconImage.png`, `CHANGELOG.md`) — deliberately NOT `Bundle.module`
/// directly, despite that being the normal way to reach SwiftPM resources.
///
/// `Bundle.module`'s generated `resource_bundle_accessor.swift` looks for
/// `vLens_vLens.bundle` at `Bundle.main.bundleURL.appendingPathComponent(...)`
/// — i.e. directly inside `vLens.app/`, a sibling of `Contents/`. That's
/// not just non-conventional, it's actively rejected by `codesign` for a
/// real signed `.app` ("unsealed contents present in the bundle root") —
/// confirmed directly while fixing the underlying bug this exists for: the
/// resource bundle was never even being copied into any release before
/// this, so every packaged build before this fix crashed with `Bundle.
/// module`'s own `fatalError` on any Mac other than the one it was built
/// on (its absolute-path build fallback happened to still exist there).
///
/// `scripts/release.sh` copies the resource bundle to the conventional
/// `Contents/Resources/` location instead; this looks for it there first,
/// falling back to `Bundle.module` for `swift run` dev builds (never
/// signed, and `Bundle.module`'s own fallback chain already handles that
/// case correctly).
enum AppResourceLocator {
    static func resourceBundle() -> Bundle {
        let packagedPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/vLens_vLens.bundle")
        if let bundle = Bundle(path: packagedPath.path) {
            return bundle
        }
        return Bundle.module
    }
}
