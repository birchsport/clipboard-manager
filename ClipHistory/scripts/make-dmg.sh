#!/usr/bin/env bash
# Build a Release .app and package it into a DMG.
#
# Usage:
#   ./scripts/make-dmg.sh              # Release build, signed with whatever's in
#                                      # Config/Signing.xcconfig (Apple Development
#                                      # by default — fine for your own Mac).
#
# Output:
#   build/ClipHistory.dmg
#
# Notes on distribution:
#   - Apple Development signing is enough for running on your own Mac.
#   - To distribute to other Macs without Gatekeeper blocking, you need a
#     "Developer ID Application" certificate and `xcrun notarytool submit` to
#     notarize, then `xcrun stapler staple` to attach the notarization. That
#     path is out of scope for this script.
set -euo pipefail

# Move to the project root (one level up from this script).
cd "$(dirname "$0")/.."

APP_NAME="ClipHistory"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
DMG_STAGING="build/dmg-staging"
DMG_PATH="build/${APP_NAME}.dmg"

echo "→ Regenerating Xcode project"
xcodegen generate >/dev/null

echo "→ Archiving Release build"
rm -rf "$ARCHIVE_PATH"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    archive \
    | grep -E "^(===|error:|warning:|\*\*|Signing Identity)" || true

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ Expected app at $APP_PATH — archive failed."
    exit 1
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

echo "✓ DMG built: $DMG_PATH"
ls -lh "$DMG_PATH"
