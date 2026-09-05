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
VERSION="1.4.3"
SIGN_IDENTITY="Developer ID Application: Canberk KILIÇARSLAN (9QB26WKA4K)"
NOTARY_PROFILE="vlens-notary"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release-package"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Syncing CHANGELOG.md into the app bundle (Help ▸ What's New)"
cp "$ROOT_DIR/CHANGELOG.md" "$ROOT_DIR/Sources/vLens/Resources/CHANGELOG.md"

echo "==> Building release binaries"
cd "$ROOT_DIR"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
VLENS_BIN="$BIN_PATH/$APP_NAME"
VLENS_CLI_BIN="$BIN_PATH/vlens-cli"
(cd helper && go build -o vlens-helper .)

echo "==> Constructing .app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"

cp "$VLENS_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# vlens-cli sits alongside vLens itself (a real executable target, not a
# bundled tool like vlens-helper) — LaunchdScheduler/AutomationCLILocator
# point at Contents/MacOS/vlens-cli for a stable launchd path (Faz 10B).
cp "$VLENS_CLI_BIN" "$APP_BUNDLE/Contents/MacOS/vlens-cli"
cp "$ROOT_DIR/helper/vlens-helper" "$APP_BUNDLE/Contents/Resources/vlens-helper"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# SwiftPM's generated resource bundle (AppIconImage.png, CHANGELOG.md) —
# this was never being copied into the packaged app at all before this fix,
# so every release crashed with a `fatalError` on any Mac other than the
# build machine (see AppResourceLocator.swift's doc comment for the full
# story, including why it's copied to Contents/Resources rather than the
# app bundle root Bundle.module's own generated accessor would look in:
# codesign rejects anything outside Contents/ — "unsealed contents present
# in the bundle root" — confirmed directly while fixing this).
RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "Resource bundle not found at $RESOURCE_BUNDLE — run 'swift build -c release' first" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

# Sparkle.framework (Faz 3 auto-update) — embedded at the conventional
# Contents/Frameworks location, matching Package.swift's linker rpath
# (@executable_path/../Frameworks). SPM's artifact checkout path is
# deterministic given Package.resolved, but found via `find` rather than
# hardcoded so a future Sparkle version bump can't silently break this.
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts/sparkle" -type d -name "Sparkle.framework" -path "*/macos-*" 2>/dev/null | head -1)"
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework not found under .build/artifacts — run 'swift build' first" >&2
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

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

# Sparkle's own nested helpers (Autoupdate, Updater.app, two XPC services)
# ship ad-hoc signed in the distributed XCFramework — they need our real
# Developer ID before notarization, but (per Sparkle's own packaging
# instructions) without our app's entitlements, which don't apply to them.
codesign_bare_with_retry() {
    local target="$1"
    local attempt
    for attempt in 1 2 3; do
        if codesign --force --options runtime --timestamp \
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

echo "==> Signing Sparkle.framework's nested code (inside out, per Sparkle's packaging instructions)"
SPARKLE_EMBEDDED="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign_bare_with_retry "$SPARKLE_EMBEDDED/Versions/B/Autoupdate"
codesign_bare_with_retry "$SPARKLE_EMBEDDED/Versions/B/Updater.app"
codesign_bare_with_retry "$SPARKLE_EMBEDDED/Versions/B/XPCServices/Downloader.xpc"
codesign_bare_with_retry "$SPARKLE_EMBEDDED/Versions/B/XPCServices/Installer.xpc"
codesign_bare_with_retry "$SPARKLE_EMBEDDED"

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

    echo "==> Signing DMG for Sparkle and writing appcast.xml"
    SPARKLE_SIGN_UPDATE="$(find "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin" -maxdepth 1 -name "sign_update" -type f 2>/dev/null | head -1)"
    if [ -z "$SPARKLE_SIGN_UPDATE" ]; then
        echo "    sign_update tool not found — skipping appcast.xml (run 'swift build' first to fetch Sparkle)" >&2
    else
        SIGNATURE_OUTPUT="$("$SPARKLE_SIGN_UPDATE" "$DMG_PATH")"
        ED_SIGNATURE="$(echo "$SIGNATURE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)"
        DMG_LENGTH="$(echo "$SIGNATURE_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)"
        BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT_DIR/Resources/Info.plist")"
        PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
        APPCAST_PATH="$ROOT_DIR/appcast.xml"

        # Pulled from CHANGELOG.md and shown right inside Sparkle's own
        # update dialog — the user is already looking at that dialog to
        # decide whether to update, so this is "what's new" without a
        # separate interruption. Keep CHANGELOG.md's [$VERSION] section
        # accurate before running this script; that's the only manual step.
        RELEASE_NOTES_HTML="$(python3 "$ROOT_DIR/scripts/changelog_section_html.py" "$ROOT_DIR/CHANGELOG.md" "$VERSION" 2>/dev/null || echo "")"

        # Single-item feed — Sparkle only needs the latest version to decide
        # "is there something newer than what's installed," it doesn't need
        # full history. The enclosure URL must exactly match where this DMG
        # ends up as a GitHub Release asset (v$VERSION tag, same filename).
        cat > "$APPCAST_PATH" << XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>vLens</title>
        <link>https://raw.githubusercontent.com/canberkys/vlens/main/appcast.xml</link>
        <description>vLens release updates</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
$RELEASE_NOTES_HTML
            ]]></description>
            <enclosure
                url="https://github.com/canberkys/vlens/releases/download/v$VERSION/$APP_NAME-$VERSION.dmg"
                length="$DMG_LENGTH"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIGNATURE" />
        </item>
    </channel>
</rss>
XML
        echo "==> Wrote $APPCAST_PATH (with release notes from CHANGELOG.md) — commit + push to main"
        echo "    (SUFeedURL reads it from raw.githubusercontent.com), and publish DMG_PATH as a GitHub"
        echo "    Release asset at tag v$VERSION with this exact filename."
    fi
else
    echo "==> Skipping notarization — no stored credentials for profile '$NOTARY_PROFILE'."
    echo "    One-time setup: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "        --apple-id <your Apple ID email> --team-id 9QB26WKA4K --password <app-specific password>"
    echo "    (generate the app-specific password at appleid.apple.com)"
    echo "==> App bundle is signed and ready at: $APP_BUNDLE (not notarized/DMG'd yet)"
fi
