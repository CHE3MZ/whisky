#!/bin/bash
#
# appcast.sh
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
# Signs a built DMG for Sparkle and writes a single-item appcast.xml.
# Release.yml attaches the result to the GitHub release; Documentation.yml
# mirrors the newest app release's appcast.xml to GitHub Pages.
#
# Usage: scripts/appcast.sh --version X.Y.Z --build BUILD --dmg PATH \
#   --repo OWNER/REPO --output PATH [--min-system VERSION] [--notes-url URL]
#
# CI sets SPARKLE_ED_PRIVATE_KEY to the base64-encoded Ed25519 private key.
# Without it, sign_update reads the key from the login keychain (local flow).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

VERSION=""
BUILD=""
DMG=""
REPO="${GITHUB_REPOSITORY:-}"
OUTPUT=""
MIN_SYSTEM=""
NOTES_URL=""

usage() {
    cat <<'EOF'
Usage: scripts/appcast.sh --version X.Y.Z --build BUILD --dmg PATH \
  --repo OWNER/REPO --output PATH [--min-system VERSION] [--notes-url URL]

Signs the DMG with Sparkle's sign_update and writes a single-item appcast.
Set SPARKLE_ED_PRIVATE_KEY to a base64-encoded private key file for CI;
otherwise the login keychain is used.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:?missing value for --version}"; shift 2 ;;
        --build) BUILD="${2:?missing value for --build}"; shift 2 ;;
        --dmg) DMG="${2:?missing value for --dmg}"; shift 2 ;;
        --repo) REPO="${2:?missing value for --repo}"; shift 2 ;;
        --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
        --min-system) MIN_SYSTEM="${2:?missing value for --min-system}"; shift 2 ;;
        --notes-url) NOTES_URL="${2:?missing value for --notes-url}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -z "$VERSION" ] || [ -z "$BUILD" ] || [ -z "$DMG" ] || \
   [ -z "$REPO" ] || [ -z "$OUTPUT" ]; then
    usage >&2
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: invalid version '$VERSION'" >&2
    exit 1
fi
if ! [[ "$BUILD" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: invalid build '$BUILD'" >&2
    exit 1
fi
if [ ! -f "$DMG" ]; then
    echo "error: DMG not found: $DMG" >&2
    exit 1
fi

if [ -z "${SPARKLE_BIN:-}" ]; then
    for derived_data in \
        "$PROJECT_DIR/build/release/DerivedData" \
        "$PROJECT_DIR/build" \
        "$HOME/Library/Developer/Xcode/DerivedData"; do
        [ -d "$derived_data" ] || continue
        SPARKLE_BIN="$(find "$derived_data" \
            -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -type d \
            2>/dev/null | head -1 || true)"
        if [ -n "$SPARKLE_BIN" ]; then
            break
        fi
    done
fi
SIGN_UPDATE="${SPARKLE_BIN:-}/sign_update"
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "error: Sparkle sign_update not found; build the app once or set SPARKLE_BIN" >&2
    exit 1
fi

KEY_FILE=""
cleanup() {
    if [ -n "$KEY_FILE" ]; then
        rm -f "$KEY_FILE"
    fi
}
trap cleanup EXIT

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/whisky-sparkle-key.XXXXXX")"
    if printf '' | base64 -D >/dev/null 2>&1; then
        printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | base64 -D > "$KEY_FILE"
    else
        printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | base64 -d > "$KEY_FILE"
    fi
    chmod 600 "$KEY_FILE"
    if [ ! -s "$KEY_FILE" ]; then
        echo "error: SPARKLE_ED_PRIVATE_KEY did not decode to a key file" >&2
        exit 1
    fi
    ATTRS="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"
else
    ATTRS="$("$SIGN_UPDATE" "$DMG")"
fi

ATTRS_FLAT="$(printf '%s' "$ATTRS" | tr '\n' ' ')"
SIGNATURE="$(printf '%s' "$ATTRS_FLAT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$ATTRS_FLAT" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "error: could not parse sign_update output: $ATTRS" >&2
    exit 1
fi

if [ -z "$MIN_SYSTEM" ]; then
    MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
        "$PROJECT_DIR/Whisky/Info.plist" 2>/dev/null || true)"
fi
MIN_SYSTEM="${MIN_SYSTEM:-15.0}"

TAG="app-v${VERSION}"
NOTES_URL="${NOTES_URL:-https://github.com/${REPO}/releases/tag/${TAG}}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/$(basename "$DMG")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Whisky</title>
        <link>https://github.com/${REPO}/releases</link>
        <description>Whisky update feed</description>
        <language>en</language>
        <item>
            <title>Whisky ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM}</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <p>See the <a href="${NOTES_URL}">release notes</a> for the full changelog.</p>
            ]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${SIGNATURE}"
                length="${LENGTH}"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
EOF

echo "Wrote $OUTPUT (Whisky $VERSION, build $BUILD, $LENGTH bytes)"
