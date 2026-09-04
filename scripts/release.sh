#!/usr/bin/env bash
set -euo pipefail

# vLens release packaging: swift build (release) -> hand-built .app bundle
# -> codesign (helper binary first, then the outer app) -> notarize (only if
# credentials are already stored) -> staple -> DMG.
#
# Deliberately no Xcode project — SwiftPM stays the single build system,
# mirroring the same developer's already-proven PkgLens release pattern
# (also SwiftPM-only, also signed/notarized this way).

APP_NAME="vLens"
VERSION="1.1.3"
SIGN_IDENTITY="Developer ID Application: Canberk KILIÇARSLAN (9QB26WKA4K)"
NOTARY_PROFILE="vlens-notary"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release-package"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binaries"
cd "$ROOT_DIR"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
VLENS_BIN="$BIN_PATH/$APP_NAME"
VLENS_CLI_BIN="$BIN_PATH/vlens-cli"
(cd helper && go build -o vlens-helper .)

echo "==> Constructing .app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$VLENS_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# vlens-cli sits alongside vLens itself (a real executable target, not a
# bundled tool like vlens-helper) — LaunchdScheduler/AutomationCLILocator
# point at Contents/MacOS/vlens-cli for a stable launchd path (Faz 10B).
cp "$VLENS_CLI_BIN" "$APP_BUNDLE/Contents/MacOS/vlens-cli"
cp "$ROOT_DIR/helper/vlens-helper" "$APP_BUNDLE/Contents/Resources/vlens-helper"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Apple's timestamp authority occasionally hiccups on a single request
# (observed directly while building this script — the second of two
# back-to-back codesign calls failed with "A timestamp was expected but was
# not found" on the first attempt, succeeded immediately on retry) — a small
# retry loop makes this script safe to run unattended.
codesign_with_retry() {
    local target="$1"
    local attempt
    for attempt in 1 2 3; do
        if codesign --force --options runtime --timestamp \
            --entitlements "$ROOT_DIR/Resources/vLens.entitlements" \
            --sign "$SIGN_IDENTITY" \
            "$target"; then
            return 0
        fi
        echo "    (codesign attempt $attempt failed, retrying...)"
        sleep 2
    done
    echo "    codesign failed after 3 attempts for $target" >&2
    return 1
}

echo "==> Signing embedded helper binary (nested code must be signed first)"
codesign_with_retry "$APP_BUNDLE/Contents/Resources/vlens-helper"

echo "==> Signing embedded vlens-cli (nested code must be signed first)"
codesign_with_retry "$APP_BUNDLE/Contents/MacOS/vlens-cli"

echo "==> Signing app bundle"
codesign_with_retry "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing (this can take a few minutes)"
    ZIP_PATH="$BUILD_DIR/$APP_NAME-notarize.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_BUNDLE"
    rm -f "$ZIP_PATH"

    echo "==> Verifying Gatekeeper acceptance"
    spctl -a -vvv --type exec "$APP_BUNDLE"

    echo "==> Packaging DMG (standard drag-to-Applications layout)"
    DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
    DMG_STAGING="$BUILD_DIR/dmg-staging"
    DMG_TEMP="$BUILD_DIR/$APP_NAME-temp.dmg"
    rm -f "$DMG_PATH" "$DMG_TEMP"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -fs HFS+ -format UDRW -ov "$DMG_TEMP"

    # Mount at the default /Volumes location (not a custom -mountpoint) —
    # Finder only recognizes a volume as a scriptable "disk" when it's
    # mounted there, discovered by trial while building this step.
    hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen

    # Lays out the two icons side by side (app on the left, an Applications
    # symlink on the right) so opening the DMG shows the standard "drag to
    # install" arrangement instead of a bare Finder window with just the
    # app in it.
    osascript <<OSA
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 660, 420}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set position of item "$APP_NAME.app" of container window to {130, 150}
        set position of item "Applications" of container window to {330, 150}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
OSA

    sync
    hdiutil detach "/Volumes/$APP_NAME"
    rm -rf "$DMG_STAGING"

    hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH"
    rm -f "$DMG_TEMP"
    echo "==> Done: $DMG_PATH"
else
    echo "==> Skipping notarization — no stored credentials for profile '$NOTARY_PROFILE'."
    echo "    One-time setup: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "        --apple-id <your Apple ID email> --team-id 9QB26WKA4K --password <app-specific password>"
    echo "    (generate the app-specific password at appleid.apple.com)"
    echo "==> App bundle is signed and ready at: $APP_BUNDLE (not notarized/DMG'd yet)"
fi
