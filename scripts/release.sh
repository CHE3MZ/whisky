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

usage() {
    cat <<'EOF'
Usage: scripts/release.sh <version>

Archives Whisky, exports and re-signs with Developer ID, builds a DMG with
create-dmg, signs and notarizes it, and staples the ticket.

Environment:
  NOTARY_PROFILE              notarytool keychain profile (default: AC_PASSWORD)
  BUILD_NUMBER                build number to inject (default: UTC timestamp)
  ARCHIVE_CODE_SIGN_STYLE     archive signing style (default: Automatic)
  ARCHIVE_CODE_SIGN_IDENTITY  archive signing identity (default: Apple Development)
  ALLOW_DIRTY=1               allow a dirty working tree
  CLEAN=1                     remove build/release before building
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        usage >&2
        exit 1
        ;;
esac

VERSION="$1"
if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: invalid version '$VERSION' (expected X.Y.Z)" >&2
    exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
ARCHIVE_CODE_SIGN_STYLE="${ARCHIVE_CODE_SIGN_STYLE:-Automatic}"
ARCHIVE_CODE_SIGN_IDENTITY="${ARCHIVE_CODE_SIGN_IDENTITY:-Apple Development}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: invalid build number '$BUILD_NUMBER'" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/Whisky.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Whisky-$VERSION.dmg"

cd "$PROJECT_DIR"

if [ "${ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "error: working tree has uncommitted changes to tracked files." >&2
    echo "       Commit them, or set ALLOW_DIRTY=1 to build anyway." >&2
    exit 1
fi

echo "==> Checking prerequisites"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg not found. Install it with: npm install --global create-dmg (Node.js 20+)" >&2
    exit 1
fi

CREATE_DMG_HELP="$(create-dmg --help 2>&1 || true)"
if [[ "$CREATE_DMG_HELP" != *--no-version-in-filename* ]]; then
    echo "error: the create-dmg on PATH is not the npm package." >&2
    echo "       Install it with: npm install --global create-dmg (Node.js 20+)" >&2
    exit 1
fi

CODESIGN_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ "$CODESIGN_IDENTITIES" != *"Developer ID Application"* ]]; then
    echo "error: no valid Developer ID Application certificate in the keychain." >&2
    echo "       See docs/ReleaseWorkflow.md for setup." >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: notarytool profile '$NOTARY_PROFILE' is missing or invalid." >&2
    echo "       Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
    echo "           --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>" >&2
    exit 1
fi

if [ "${CLEAN:-0}" = "1" ]; then
    echo "==> Removing $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

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
    -derivedDataPath "$BUILD_DIR/DerivedData" \
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
    -exportOptionsPlist scripts/config/exportOptions.plist \
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
NOTARY_RESULT="$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json)"
NOTARY_STATUS="$(printf '%s' "$NOTARY_RESULT" | plutil -extract status raw -o - - 2>/dev/null || true)"
if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "error: notarization did not succeed (status: ${NOTARY_STATUS:-unknown})" >&2
    NOTARY_ID="$(printf '%s' "$NOTARY_RESULT" | plutil -extract id raw -o - - 2>/dev/null || true)"
    if [ -n "$NOTARY_ID" ]; then
        echo "==> Fetching notarization log" >&2
        xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    else
        printf '%s\n' "$NOTARY_RESULT" >&2
    fi
    exit 1
fi

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying stapled DMG"
xcrun stapler validate "$DMG_PATH"
if ! spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"; then
    echo "warning: spctl assessment failed; stapler validate passed, but Gatekeeper may still reject the DMG." >&2
fi

echo
echo "Build artifact: $DMG_PATH"
echo "Version: $VERSION (build $BUILD_NUMBER)"
echo "$BUILD_NUMBER" > "$BUILD_DIR/build-number.txt"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    # shellcheck disable=SC2016  # the backticks are Markdown, not a substitution
    printf '**Version:** `%s` (build `%s`)\n' "$VERSION" "$BUILD_NUMBER" >> "$GITHUB_STEP_SUMMARY"
fi
shasum -a 256 "$DMG_PATH"
