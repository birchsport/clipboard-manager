#!/usr/bin/env bash
# Build a signed (and optionally notarized) DMG.
#
# Usage:
#   ./scripts/make-dmg.sh
#       Build a Release DMG signed with whatever identity the Release config
#       selects from your keychain (Developer ID Application by default).
#       No notarization — fine for use on your own Mac, will be blocked by
#       Gatekeeper on other Macs.
#
#   NOTARY_PROFILE=notarytool-birchboard ./scripts/make-dmg.sh
#       Same, but after building, codesign the DMG, submit it to Apple's
#       notary service, wait for approval, and staple the ticket so it
#       validates offline. The resulting DMG is safe to send to other Macs.
#
# See the "Distributing to other Macs" section in README.md for the
# one-time setup (getting a Developer ID cert, creating the
# app-specific password, and `xcrun notarytool store-credentials`).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Birchboard"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
DMG_STAGING="build/dmg-staging"
DMG_PATH="build/${APP_NAME}.dmg"
SIGN_ID="${SIGN_IDENTITY:-Developer ID Application}"

echo "→ Regenerating Xcode project"
xcodegen generate >/dev/null

echo "→ Archiving Release build"
rm -rf "$ARCHIVE_PATH"
mkdir -p build
LOG_PATH="build/xcodebuild-archive.log"

# Tee to a log file and filter common interesting lines for the terminal. Using
# an explicit if-block so a non-zero exit from xcodebuild surfaces the tail of
# the log — earlier versions of this script hid real errors behind a grep
# filter that only matched lines beginning with certain tokens.
set +e
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    archive > "$LOG_PATH" 2>&1
ARCHIVE_STATUS=$?
set -e

grep -E "(===|error:|warning:|\*\*|Signing Identity)" "$LOG_PATH" || true

if [[ $ARCHIVE_STATUS -ne 0 ]]; then
    echo ""
    echo "✗ archive failed (exit $ARCHIVE_STATUS). Tail of $LOG_PATH:"
    echo "────────────────────────────────────────────────────────────"
    tail -40 "$LOG_PATH"
    echo "────────────────────────────────────────────────────────────"
    exit 1
fi

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ Expected app at $APP_PATH — archive reported success but produced no .app."
    exit 1
fi

# ---------------------------------------------------------------------
# Re-sign Sparkle's nested binaries.
# ---------------------------------------------------------------------
# Sparkle 2 distributes as an XCFramework with its XPC services and helper
# binaries pre-signed by the Sparkle Project. xcodebuild archive re-signs
# the outer Sparkle.framework wrapper but leaves the nested binaries with
# their original signatures, so the notary service rejects them with
# "The binary is not signed with a valid Developer ID certificate" and
# "The signature does not include a secure timestamp."
#
# Fix: walk the known nested bundle/binary paths and re-sign each with our
# Developer ID + --timestamp + hardened runtime. Order matters — sign
# deepest children first so outer wrappers include the new inner hashes
# when we sign them in turn.
SPARKLE_BASE="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$SPARKLE_BASE" ]]; then
    echo "→ Re-signing nested Sparkle binaries with $SIGN_ID"
    for nested in \
        "$SPARKLE_BASE/XPCServices/Downloader.xpc" \
        "$SPARKLE_BASE/XPCServices/Installer.xpc" \
        "$SPARKLE_BASE/Autoupdate" \
        "$SPARKLE_BASE/Updater.app"; do
        if [[ -e "$nested" ]]; then
            codesign --force \
                --sign "$SIGN_ID" \
                --timestamp \
                --options runtime \
                --preserve-metadata=identifier,entitlements \
                "$nested"
        fi
    done
    # Re-sign the Sparkle.framework wrapper so its new hash tree matches
    # the nested bundles we just touched.
    codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
        "$APP_PATH/Contents/Frameworks/Sparkle.framework"
    # And finally the app itself — its code-directory hash covers
    # Sparkle.framework, which just changed.
    codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
        --preserve-metadata=entitlements \
        "$APP_PATH"
    # Sanity: verify the fully-signed app before we bother building a
    # DMG and submitting to notarization.
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

echo "→ Preparing DMG staging directory"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "→ Creating DMG"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGING"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    # Sign the DMG with the same Developer ID identity as the app. codesign
    # resolves "Developer ID Application" by prefix when a single matching
    # certificate is in the keychain; if you have multiple, pass the full
    # identity string via SIGN_IDENTITY.
    echo "→ Signing DMG (${SIGN_ID})"
    codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"

    echo "→ Notarizing (profile: ${NOTARY_PROFILE}). This can take 1–5 minutes."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "→ Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"

    echo "→ Verifying Gatekeeper acceptance"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" || true
else
    echo "ℹ Skipping notarization (NOTARY_PROFILE not set). The DMG will"
    echo "  work on your Mac but Gatekeeper will block it on others."
fi

echo "✓ DMG built: $DMG_PATH"
ls -lh "$DMG_PATH"
