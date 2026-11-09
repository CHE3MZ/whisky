#!/bin/bash
#
# release.sh
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Builds, signs, notarizes, staples, and packages Whisky.app as a DMG.
#
# Prerequisites:
#   - Developer ID Application certificate installed in Keychain
#   - notarytool credentials stored under profile name "AC_PASSWORD"
#   - create-dmg (npm install --global create-dmg, Node.js 20+)
#
# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 3.0.0

set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
ARCHIVE_CODE_SIGN_STYLE="${ARCHIVE_CODE_SIGN_STYLE:-Automatic}"
ARCHIVE_CODE_SIGN_IDENTITY="${ARCHIVE_CODE_SIGN_IDENTITY:-Apple Development}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg not found. Install it with: npm install --global create-dmg (Node.js 20+)" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/Whisky.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Whisky-$VERSION.dmg"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving Whisky $VERSION (build $BUILD_NUMBER)"
ARCHIVE_SIGNING_ARGS=(
    CODE_SIGN_STYLE="$ARCHIVE_CODE_SIGN_STYLE"
    CODE_SIGN_IDENTITY="$ARCHIVE_CODE_SIGN_IDENTITY"
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)
if [ "$ARCHIVE_CODE_SIGN_STYLE" = "Manual" ]; then
    ARCHIVE_SIGNING_ARGS+=(PROVISIONING_PROFILE_SPECIFIER="")
fi
xcodebuild \
    -project Whisky.xcodeproj \
    -scheme Whisky \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    "${ARCHIVE_SIGNING_ARGS[@]}" \
    archive

echo "==> Exporting and re-signing with Developer ID"
rm -rf "$EXPORT_PATH"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist scripts/exportOptions.plist \
    -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/Whisky.app"
[ -d "$APP_PATH" ] || { echo "Whisky.app not found at $APP_PATH"; exit 1; }

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "error: built app reports version '$BUILT_VERSION' but release requested '$VERSION'" >&2
    echo "       MARKETING_VERSION was not applied by the archive step." >&2
    exit 1
fi
if [ "$BUILT_BUILD" != "$BUILD_NUMBER" ]; then
    echo "error: built app reports build '$BUILT_BUILD' but release requested '$BUILD_NUMBER'" >&2
    echo "       CURRENT_PROJECT_VERSION was not applied by the archive step." >&2
    exit 1
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Building styled DMG with create-dmg"
rm -f "$DMG_PATH" "$BUILD_DIR/Whisky.dmg"
create-dmg \
    "$APP_PATH" \
    "$BUILD_DIR" \
    --overwrite \
    --no-version-in-filename \
    --no-code-sign \
    --dmg-title="Whisky"
[ -f "$BUILD_DIR/Whisky.dmg" ] || {
    echo "error: create-dmg did not produce $BUILD_DIR/Whisky.dmg" >&2
    exit 1
}
mv "$BUILD_DIR/Whisky.dmg" "$DMG_PATH"

echo "==> Signing DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"

echo "==> Submitting to notary service (this can take several minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying stapled DMG"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || true

echo
echo "Build artifact: $DMG_PATH"
echo "Version: $VERSION (build $BUILD_NUMBER)"
echo "$BUILD_NUMBER" > "$BUILD_DIR/build-number.txt"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '**Version:** `%s` (build `%s`)\n' "$VERSION" "$BUILD_NUMBER" >> "$GITHUB_STEP_SUMMARY"
fi
shasum -a 256 "$DMG_PATH"
