#!/bin/bash
#
# runtime.sh
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
# Builds a Wine Libraries runtime from the pinned upstream release assets:
# downloads Wine (Gcenx), DXVK (Gcenx) and DXMT (3Shain), verifies each against
# its SHA-256, assembles the Libraries/ tree the app expects, and repacks it as
# Libraries.tar.gz.
#
# Version pins, release asset names and their SHA-256 checksums all live in
# scripts/config/sources.yml.
#
# Usage: scripts/runtime.sh <new-version> [options]
#   --dry-run          Print the plan; download and write nothing.
#   --output PATH      Archive path (default: scripts/runtime/release/Libraries-runtime-vX.Y.Z.tar.gz).
#   --workdir DIR      Build/cache dir (default: scripts/runtime/build).
#   --keep             Keep a temp workdir after a build (only affects --dry-run).
#   --sources PATH     Pin list (default: scripts/config/sources.yml).
#   --write-plist      Generate build/WhiskyWineVersion.plist from the built archive.
#   -h, --help         Show this help.
#
# A real build needs macOS: shasum, plutil, xattr, perl, curl and bsdtar.
# --dry-run only needs the standard text tools, so CI can validate the config
# anywhere.

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SOURCES_FILE="$SCRIPT_DIR/config/sources.yml"
BUILD_DIR="$SCRIPT_DIR/runtime/build"
RELEASE_DIR="$SCRIPT_DIR/runtime/release"
RELEASE_REPO=${WHISKY_REPO:-CHE3MZ/whisky}

NEW_VERSION=''
OUTPUT_FILE=''
WORKDIR_ARG=''
DRY_RUN=0
KEEP=0
WRITE_PLIST=0
SEP=$(printf '\034')
WORK=''
WORK_IS_TEMP=0
SOURCES_PARSED=''

usage() {
    cat <<'EOF'
Usage: scripts/runtime.sh <new-version> [options]

Builds Libraries.tar.gz from the pinned Wine, DXVK and DXMT release assets.

Options:
  --dry-run          Print the plan; download and write nothing
  --output PATH      Archive path (default: scripts/runtime/release/Libraries-runtime-vX.Y.Z.tar.gz)
  --workdir DIR      Build/cache dir (default: scripts/runtime/build)
  --keep             Keep a temp workdir after a build (only affects --dry-run)
  --sources PATH     Pin list (default: scripts/config/sources.yml)
  --write-plist      Generate build/WhiskyWineVersion.plist from the built archive
  -h, --help         Show this help

Environment:
  WHISKY_REPO        Release repository (default: CHE3MZ/whisky)
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '==> %s\n' "$*"
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

sha256_of() {
    shasum -a 256 "$1" | awk '{print $1}'
}

semver_of() {
    printf '%s\n' "$1" | sed -E 's/^v?([0-9]+(\.[0-9]+)+).*/\1/'
}

github_slug() {
    slug=$1
    slug=${slug#https://}
    slug=${slug#http://}
    slug=${slug#www.}
    case "$slug" in
        github.com/*) slug=${slug#github.com/} ;;
        *) return 1 ;;
    esac
    slug=${slug%/}
    slug=${slug%.git}
    owner=${slug%%/*}
    rest=${slug#*/}
    repo=${rest%%/*}
    if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$slug" ]; then
        return 1
    fi
    printf '%s/%s\n' "$owner" "$repo"
}

# Emits "<id>\034<link>\034<commit>\034<release>" per source entry.
parse_sources() {
    tr -d '\r' < "$1" | awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function scalar(s) {
            s = trim(s)
            if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
            if (s == "null" || s == "~") s = ""
            return s
        }
        function set_field(line,    key, value) {
            key = line
            sub(/:.*/, "", key)
            value = line
            sub(/^[^:]*:[ \t]*/, "", value)
            key = trim(key)
            if (key == "id")
                id = scalar(value)
            else if (key == "link")
                link = scalar(value)
            else if (key == "commit")
                commit = scalar(value)
            else if (key == "release")
                release = scalar(value)
            else if (key == "asset")
                asset = scalar(value)
            else if (key == "sha256")
                sha = scalar(value)
        }
        function emit() {
            if (active && section == "sources")
                printf "%s\034%s\034%s\034%s\034%s\034%s\n", id, link, commit, release, asset, sha
            active = 0
            id = link = commit = release = asset = sha = ""
        }
        /^[A-Za-z_][A-Za-z0-9_]*[ \t]*:/ {
            emit()
            section = $0
            sub(/:.*/, "", section)
            section = trim(section)
            next
        }
        /^[ \t]*-[ \t]+/ {
            emit()
            active = 1
            line = $0
            sub(/^[ \t]*-[ \t]+/, "", line)
            set_field(line)
            next
        }
        /^[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*:/ {
            line = $0
            sub(/^[ \t]+/, "", line)
            set_field(line)
            next
        }
        END { emit() }
    '
}

source_field() {
    awk -F"$SEP" -v id="$1" -v n="$2" '$1 == id { print $n; exit }' "$SOURCES_PARSED"
}

# Loads a component's source row into C_RELEASE, C_ASSET, C_SHA, C_SLUG, C_URL.
# Component ids map to the sources.yml `id`s; asset + sha256 live on that row.
load_component() {
    case "$1" in
        wine) source_id="WINE" ;;
        dxvk) source_id="DXVK" ;;
        dxmt) source_id="DXMT" ;;
        *) die "unknown component: $1" ;;
    esac
    C_LINK=$(source_field "$source_id" 2)
    C_RELEASE=$(source_field "$source_id" 4)
    C_ASSET=$(source_field "$source_id" 5)
    C_SHA=$(source_field "$source_id" 6)
    [ -n "$C_LINK" ] || die "$SOURCES_FILE: source '$source_id' has no link"
    [ -n "$C_RELEASE" ] || die "$SOURCES_FILE: source '$source_id' has no release pin"
    [ -n "$C_ASSET" ] || die "$SOURCES_FILE: source '$source_id' has no asset"
    [[ "$C_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || die "$SOURCES_FILE: source '$source_id' has an invalid sha256"
    case "$C_ASSET" in
        *"$C_RELEASE"*) ;;
        *) die "$SOURCES_FILE: source '$source_id' asset '$C_ASSET' does not contain release '$C_RELEASE' (bump both)" ;;
    esac
    C_SLUG=$(github_slug "$C_LINK") || die "$SOURCES_FILE: source '$source_id' is not a GitHub repo: $C_LINK"
    C_URL="https://github.com/$C_SLUG/releases/download/$C_RELEASE/$C_ASSET"
}

cleanup() {
    if [ "$WORK_IS_TEMP" -eq 1 ] && [ "$KEEP" -eq 0 ]; then
        rm -rf "$WORK"
    fi
    if [ "$KEEP" -eq 1 ] || [ "$WORK_IS_TEMP" -eq 0 ]; then
        printf 'workdir: %s\n' "$WORK"
    fi
}

strip_builtin_marker() {
    perl -e '
        my $f = $ARGV[0];
        open my $h, "+<", $f or die "$f: $!";
        binmode $h;
        seek $h, 0x40, 0;
        read $h, my $sig, 16;
        if ($sig eq "Wine builtin DLL") {
            seek $h, 0x40, 0;
            print $h "\x0e\x1f\xba\x0e\x00\xb4\x09\xcd\x21\xb8\x01\x4c\xcd\x21\x90\x90";
        } else {
            die "$f: expected builtin marker at 0x40, found \x22$sig\x22 - DXMT layout changed?";
        }
        close $h;
    ' "$1"
}

download_asset() {
    dest="$WORK/downloads/$C_ASSET"
    if [ -f "$dest" ]; then
        cached_sha=$(sha256_of "$dest")
        if [ "$cached_sha" = "$C_SHA" ]; then
            log "cached $C_ASSET"
            return 0
        fi
    fi
    log "downloading $C_ASSET ($C_SLUG@$C_RELEASE)"
    curl -fL --retry 3 --connect-timeout 15 --max-time 600 -o "$dest" "$C_URL"
    actual=$(sha256_of "$dest")
    if [ "$actual" != "$C_SHA" ]; then
        die "$C_ASSET: SHA-256 mismatch (expected $C_SHA, got $actual)"
    fi
}

extract_into() {
    dest="$WORK/src/$2"
    mkdir -p "$dest"
    tar -xf "$WORK/downloads/$1" -C "$dest"
}

first_dir_with() {
    for candidate in "$1"/*/; do
        [ -d "$candidate/$2" ] && { printf '%s\n' "${candidate%/}"; return 0; }
    done
    return 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --keep)
            KEEP=1
            ;;
        --output)
            [ $# -ge 2 ] || die "--output needs a path"
            OUTPUT_FILE=$2
            shift
            ;;
        --workdir)
            [ $# -ge 2 ] || die "--workdir needs a path"
            WORKDIR_ARG=$2
            shift
            ;;
        --sources)
            [ $# -ge 2 ] || die "--sources needs a path"
            SOURCES_FILE=$2
            shift
            ;;
        --write-plist)
            WRITE_PLIST=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            [ -z "$NEW_VERSION" ] || die "unexpected argument: $1"
            NEW_VERSION=$1
            ;;
    esac
    shift
done

if [ -z "$NEW_VERSION" ]; then
    usage >&2
    exit 2
fi
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z (got: $NEW_VERSION)"
IFS='.' read -r MAJOR MINOR PATCH <<< "$NEW_VERSION"

[ -f "$SOURCES_FILE" ] || die "sources file not found: $SOURCES_FILE"

if [ "$DRY_RUN" -ne 1 ]; then
    kernel=$(uname -s)
    [ "$kernel" = "Darwin" ] || die "a real build needs macOS; use --dry-run elsewhere"
fi

if [ -n "$WORKDIR_ARG" ]; then
    mkdir -p "$WORKDIR_ARG"
    WORK=$(CDPATH='' cd "$WORKDIR_ARG" && pwd)
    WORK_IS_TEMP=0
elif [ "$DRY_RUN" -eq 1 ]; then
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/whisky-runtime.XXXXXX")
    WORK_IS_TEMP=1
else
    mkdir -p "$BUILD_DIR"
    WORK=$(CDPATH='' cd "$BUILD_DIR" && pwd)
    WORK_IS_TEMP=0
fi
trap cleanup EXIT

SOURCES_PARSED="$WORK/sources.parsed"
parse_sources "$SOURCES_FILE" > "$SOURCES_PARSED"

load_component wine
WINE_RELEASE=$C_RELEASE
WINE_ASSET=$C_ASSET
WINE_SHA=$C_SHA
WINE_URL=$C_URL

load_component dxvk
DXVK_RELEASE=$C_RELEASE
DXVK_ASSET=$C_ASSET
DXVK_SHA=$C_SHA
DXVK_URL=$C_URL
DXVK_VERSION=$(semver_of "$DXVK_RELEASE")

load_component dxmt
DXMT_RELEASE=$C_RELEASE
DXMT_ASSET=$C_ASSET
DXMT_SHA=$C_SHA
DXMT_URL=$C_URL
DXMT_VERSION=$(semver_of "$DXMT_RELEASE")

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$RELEASE_DIR/Libraries-runtime-v$NEW_VERSION.tar.gz"
else
    case "$OUTPUT_FILE" in
        /*) ;;
        *) OUTPUT_FILE="$PWD/$OUTPUT_FILE" ;;
    esac
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Runtime plan for runtime-v%s\n\n' "$NEW_VERSION"
    printf 'sources: %s\noutput:  %s\n' "$SOURCES_FILE" "$OUTPUT_FILE"
    if [ "$WRITE_PLIST" -eq 1 ]; then
        printf 'plist:   %s (would generate)\n' "$SCRIPT_DIR/../build/WhiskyWineVersion.plist"
    fi
    printf '\n'
    printf 'wine\n  release: %s\n  asset:   %s\n  sha256:  %s\n  url:     %s\n\n' \
        "$WINE_RELEASE" "$WINE_ASSET" "$WINE_SHA" "$WINE_URL"
    printf 'dxvk %s\n  release: %s\n  asset:   %s\n  sha256:  %s\n  url:     %s\n\n' \
        "$DXVK_VERSION" "$DXVK_RELEASE" "$DXVK_ASSET" "$DXVK_SHA" "$DXVK_URL"
    printf 'dxmt %s\n  release: %s\n  asset:   %s\n  sha256:  %s\n  url:     %s\n\n' \
        "$DXMT_VERSION" "$DXMT_RELEASE" "$DXMT_ASSET" "$DXMT_SHA" "$DXMT_URL"
    printf 'layers:\n  Libraries/Wine/bin/wine64 -> wine\n  Libraries/DXVK/{x64,x32}\n  Libraries/DXMT/{x64,x32} (native trio + winemetal)\n  Libraries/WhiskyWineVersion.plist\n'
    exit 0
fi

need curl
need shasum
need tar
need plutil
need xattr
need perl
need sed
need awk

mkdir -p "$WORK/downloads"
rm -rf "$WORK/src" "$WORK/stage"
LIB="$WORK/stage/Libraries"
mkdir -p "$LIB"

# 1. Wine: take the inner tree from Gcenx's app bundle and add the wine64 the
#    app launches (upstream ships only `bin/wine`; Whisky's base added this).
load_component wine
download_asset
extract_into "$WINE_ASSET" wine
WINE_SRC="$WORK/src/wine/Wine Stable.app/Contents/Resources/wine"
[ -d "$WINE_SRC" ] || die "unexpected Wine layout (no $WINE_SRC)"
cp -R "$WINE_SRC" "$LIB/Wine"
[ -f "$LIB/Wine/bin/wine" ] || die "Wine layout changed: bin/wine missing"
ln -sf wine "$LIB/Wine/bin/wine64"
[ -e "$LIB/Wine/bin/wine64" ] || die "failed to create Wine/bin/wine64"
# Match the published runtime: drop winemenubuilder so Wine never registers host
# menu entries or file associations.
rm -f "$LIB/Wine/lib/wine/x86_64-windows/winemenubuilder.exe"

# 2. DXVK: the non-builtin macOS asset ships native x64/ and x32/ trees with
#    no dxgi.dll, which is exactly what the app deploys per bottle.
load_component dxvk
download_asset
extract_into "$DXVK_ASSET" dxvk
DXVK_SRC=$(first_dir_with "$WORK/src/dxvk" x64) || die "unexpected DXVK layout"
mkdir -p "$LIB/DXVK"
cp -R "$DXVK_SRC/x64" "$LIB/DXVK/x64"
cp -R "$DXVK_SRC/x32" "$LIB/DXVK/x32"
# The published runtime carries DXVK's default config alongside the DLLs.
if [ -f "$DXVK_SRC/dxvk.conf" ]; then
    cp "$DXVK_SRC/dxvk.conf" "$LIB/DXVK/dxvk.conf"
fi
[ -f "$LIB/DXVK/x64/d3d11.dll" ] || die "DXVK layout changed: x64/d3d11.dll missing"

# 3. DXMT: strip the builtin marker off the trio so they load native per bottle,
#    keep winemetal builtin by pairing it with its unixlib, and ship the license.
load_component dxmt
download_asset
extract_into "$DXMT_ASSET" dxmt
DXMT_SRC=$(first_dir_with "$WORK/src/dxmt" x86_64-windows) || die "unexpected DXMT layout"
mkdir -p "$LIB/DXMT/x64" "$LIB/DXMT/x32"
cp "$DXMT_SRC/x86_64-windows/"*.dll "$LIB/DXMT/x64/"
cp "$DXMT_SRC/i386-windows/"*.dll "$LIB/DXMT/x32/"
for arch in x64 x32; do
    for dll in d3d11.dll dxgi.dll d3d10core.dll; do
        strip_builtin_marker "$LIB/DXMT/$arch/$dll"
    done
done
UNIXLIB="$LIB/Wine/lib/wine/x86_64-unix"
[ -d "$UNIXLIB" ] || die "Wine layout changed: $UNIXLIB missing"
cp "$DXMT_SRC/x86_64-unix/winemetal.so" "$UNIXLIB/winemetal.so"
cp "$LIB/DXMT/x64/winemetal.dll" "$LIB/Wine/lib/wine/x86_64-windows/winemetal.dll"
cp "$LIB/DXMT/x32/winemetal.dll" "$LIB/Wine/lib/wine/i386-windows/winemetal.dll"
curl -fL --retry 3 --connect-timeout 15 -o "$LIB/DXMT/LICENSE" \
    "https://raw.githubusercontent.com/$C_SLUG/$DXMT_RELEASE/LICENSE"

# 4. Version record read by the app after install.
PLIST="$LIB/WhiskyWineVersion.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>version</key>
	<dict>
		<key>major</key>
		<integer>$MAJOR</integer>
		<key>minor</key>
		<integer>$MINOR</integer>
		<key>patch</key>
		<integer>$PATCH</integer>
	</dict>
	<key>dxvkVersion</key>
	<string>$DXVK_VERSION</string>
	<key>dxmtVersion</key>
	<string>$DXMT_VERSION</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null

# 5. Drop quarantine and other xattrs, then repack. COPYFILE_DISABLE avoids
#    ._ AppleDouble entries; --no-xattrs keeps xattrs out of the archive.
xattr -rc "$LIB" 2>/dev/null || true
mkdir -p "$(dirname "$OUTPUT_FILE")"
rm -f "$OUTPUT_FILE"
( cd "$WORK/stage" && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$OUTPUT_FILE" Libraries )

DIGEST=$(sha256_of "$OUTPUT_FILE")

if [ "$WRITE_PLIST" -eq 1 ]; then
    log "Generating build/WhiskyWineVersion.plist"
    bash "$SCRIPT_DIR/runtime/sync.sh" --archive "$OUTPUT_FILE"
    DOCS_STEP="  3. build/WhiskyWineVersion.plist generated from the archive.
     Attach it to the runtime release as WhiskyWineVersion.plist and record the
     digest in docs/misc/dependencies.md."
else
    DOCS_STEP="  3. Generate WhiskyWineVersion.plist with version $NEW_VERSION,
     sha256 $DIGEST and dxmtVersion $DXMT_VERSION (or rerun with --write-plist),
     then attach it to the runtime release."
fi

printf '\nAssembled: %s\n' "$OUTPUT_FILE"
printf 'SHA-256:   %s\n' "$DIGEST"
printf 'Runtime:   runtime-v%s (Wine %s, DXVK %s, DXMT %s)\n' "$NEW_VERSION" "$WINE_RELEASE" "$DXVK_VERSION" "$DXMT_VERSION"

cat <<SUMMARY

Next:
  1. Smoke test: install the archive locally, verify bottles + DXVK still work,
     then set a bottle to DXMT and launch a D3D11 title. The trio must load
     native and winemetal builtin:
       grep -aL 'Wine builtin DLL' "$WORK/stage/Libraries/DXMT/x64/d3d11.dll"
       grep -al 'Wine builtin DLL' "$WORK/stage/Libraries/Wine/lib/wine/x86_64-windows/winemetal.dll"
  2. Publish (assets must be named exactly Libraries.tar.gz and WhiskyWineVersion.plist):
       cp "$OUTPUT_FILE" Libraries.tar.gz
       bash "$SCRIPT_DIR/runtime/sync.sh" --archive "$OUTPUT_FILE" --output WhiskyWineVersion.plist
       gh release create runtime-v$NEW_VERSION --repo $RELEASE_REPO \\
         --title "Wine Libraries v$NEW_VERSION" \\
         --notes "..." Libraries.tar.gz WhiskyWineVersion.plist
$DOCS_STEP
  4. For a future runtime, bump the release and the matching asset + sha256 in
     scripts/config/sources.yml, then run scripts/upstream/report.sh.
SUMMARY
