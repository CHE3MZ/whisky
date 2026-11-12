#!/bin/bash
#
# sync.sh
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
# Syncs docs/WhiskyWineVersion.plist from a built Libraries.tar.gz:
#   - reads Libraries/WhiskyWineVersion.plist from the archive
#   - computes the archive SHA-256
#   - writes version, dxvkVersion, dxmtVersion and sha256 to the docs plist
#
# Usage: scripts/runtime/sync.sh [--archive PATH] [--output PATH] [--check]
#   --archive PATH  Archive to read (default: newest scripts/runtime/release/Libraries-v*.tar.gz)
#   --output PATH   Plist to write (default: docs/WhiskyWineVersion.plist)
#   --check         Exit 1 if the plist is out of date; do not write
#   -h, --help      Show this help

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH='' cd "$SCRIPT_DIR/../.." && pwd)
RELEASE_DIR="$SCRIPT_DIR/release"
DEFAULT_OUTPUT="$PROJECT_DIR/docs/WhiskyWineVersion.plist"

ARCHIVE=''
OUTPUT=$DEFAULT_OUTPUT
CHECK=0
TMP_DIR=''

usage() {
    cat <<'EOF'
Usage: scripts/runtime/sync.sh [--archive PATH] [--output PATH] [--check]

Syncs docs/WhiskyWineVersion.plist from a built Libraries.tar.gz.

Options:
  --archive PATH  Archive to read (default: newest scripts/runtime/release/Libraries-v*.tar.gz)
  --output PATH   Plist to write (default: docs/WhiskyWineVersion.plist)
  --check         Exit 1 if the plist is out of date; do not write
  -h, --help      Show this help
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

cleanup() {
    if [ -n "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        die "shasum or sha256sum is required"
    fi
}

find_default_archive() {
    local candidate
    for candidate in "$RELEASE_DIR"/Libraries-v*.tar.gz; do
        [ -f "$candidate" ] || continue
        if [ -z "$ARCHIVE" ] || [ "$candidate" -nt "$ARCHIVE" ]; then
            ARCHIVE=$candidate
        fi
    done
    [ -n "$ARCHIVE" ] || die "no archive found; pass --archive"
}

extract_plist() {
    if ! tar -xOf "$ARCHIVE" Libraries/WhiskyWineVersion.plist > "$TMP_PLIST" 2>/dev/null; then
        tar -xOf "$ARCHIVE" ./Libraries/WhiskyWineVersion.plist > "$TMP_PLIST" \
            || die "archive does not contain Libraries/WhiskyWineVersion.plist"
    fi
}

plist_value() {
    awk -v key="$1" '
        index($0, "<key>" key "</key>") {
            getline
            sub(/^[[:space:]]*<(integer|string)>/, "")
            sub(/<\/(integer|string)>.*/, "")
            print
            exit
        }
    ' "$TMP_PLIST"
}

read_plist() {
    if command -v plutil >/dev/null 2>&1; then
        MAJOR=$(plutil -extract version.major raw -o - "$TMP_PLIST")
        MINOR=$(plutil -extract version.minor raw -o - "$TMP_PLIST")
        PATCH=$(plutil -extract version.patch raw -o - "$TMP_PLIST")
        DXVK_VERSION=$(plutil -extract dxvkVersion raw -o - "$TMP_PLIST")
        DXMT_VERSION=$(plutil -extract dxmtVersion raw -o - "$TMP_PLIST")
    elif command -v python3 >/dev/null 2>&1; then
        local values
        values=$(python3 - "$TMP_PLIST" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    info = plistlib.load(handle)

version = info.get("version") or {}
print(version.get("major", ""))
print(version.get("minor", ""))
print(version.get("patch", ""))
print(info.get("dxvkVersion", ""))
print(info.get("dxmtVersion", ""))
PY
)
        {
            IFS= read -r MAJOR || true
            IFS= read -r MINOR || true
            IFS= read -r PATCH || true
            IFS= read -r DXVK_VERSION || true
            IFS= read -r DXMT_VERSION || true
        } <<< "$values"
    else
        MAJOR=$(plist_value major)
        MINOR=$(plist_value minor)
        PATCH=$(plist_value patch)
        DXVK_VERSION=$(plist_value dxvkVersion)
        DXMT_VERSION=$(plist_value dxmtVersion)
    fi
}

write_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>dxmtVersion</key>
	<string>$DXMT_VERSION</string>
	<key>dxvkVersion</key>
	<string>$DXVK_VERSION</string>
	<key>sha256</key>
	<string>$SHA256</string>
	<key>version</key>
	<dict>
		<key>major</key>
		<integer>$MAJOR</integer>
		<key>minor</key>
		<integer>$MINOR</integer>
		<key>patch</key>
		<integer>$PATCH</integer>
	</dict>
</dict>
</plist>
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --archive)
            [ $# -ge 2 ] || die "--archive needs a path"
            ARCHIVE=$2
            shift
            ;;
        --output)
            [ $# -ge 2 ] || die "--output needs a path"
            OUTPUT=$2
            shift
            ;;
        --check)
            CHECK=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
    shift
done

need tar
need awk
need mktemp

if [ -z "$ARCHIVE" ]; then
    find_default_archive
else
    case "$ARCHIVE" in
        /*) ;;
        *) ARCHIVE="$PWD/$ARCHIVE" ;;
    esac
fi
[ -f "$ARCHIVE" ] || die "archive not found: $ARCHIVE"

case "$OUTPUT" in
    /*) ;;
    *) OUTPUT="$PWD/$OUTPUT" ;;
esac

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/whisky-plist.XXXXXX")
trap cleanup EXIT
TMP_PLIST="$TMP_DIR/WhiskyWineVersion.plist"
TMP_OUTPUT="$TMP_DIR/WhiskyWineVersion.out.plist"

extract_plist
read_plist

[[ "$MAJOR" =~ ^[0-9]+$ ]] || die "invalid version.major in archive: $MAJOR"
[[ "$MINOR" =~ ^[0-9]+$ ]] || die "invalid version.minor in archive: $MINOR"
[[ "$PATCH" =~ ^[0-9]+$ ]] || die "invalid version.patch in archive: $PATCH"
[ -n "$DXVK_VERSION" ] || die "archive plist has no dxvkVersion"
[ -n "$DXMT_VERSION" ] || die "archive plist has no dxmtVersion"

SHA256=$(sha256_of "$ARCHIVE")
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || die "invalid SHA-256 for archive: $SHA256"

write_plist > "$TMP_OUTPUT"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$TMP_OUTPUT" >/dev/null
fi

if [ "$CHECK" -eq 1 ]; then
    need cmp
    if [ ! -f "$OUTPUT" ]; then
        printf 'missing: %s\n' "$OUTPUT" >&2
        exit 1
    fi
    if cmp -s "$TMP_OUTPUT" "$OUTPUT"; then
        printf 'up to date: %s\n' "$OUTPUT"
        exit 0
    fi
    printf 'out of date: %s\n' "$OUTPUT" >&2
    if command -v diff >/dev/null 2>&1; then
        diff -u "$OUTPUT" "$TMP_OUTPUT" || true
    fi
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
cp "$TMP_OUTPUT" "$OUTPUT"
printf 'Updated %s\n' "$OUTPUT"
printf 'Runtime: v%s.%s.%s (DXVK %s, DXMT %s)\n' \
    "$MAJOR" "$MINOR" "$PATCH" "$DXVK_VERSION" "$DXMT_VERSION"
printf 'SHA-256: %s\n' "$SHA256"
