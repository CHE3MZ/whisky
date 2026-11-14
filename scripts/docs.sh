#!/bin/bash
#
# docs.sh
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
# Builds the GitHub Pages site into site:
#   - the MkDocs site from docs/ (requires mkdocs)
#   - the newest runtime-v release's WhiskyWineVersion.plist (requires gh);
#     falls back to the deployed plist, or is absent if neither exists
#   - DocC for WhiskyKit (requires macOS with Xcode)
#   - the newest app release's appcast.xml (requires gh)
#
# Usage: scripts/docs.sh [--no-appcast] [--no-plist]
# Example: scripts/docs.sh --no-appcast --no-plist

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/docs.sh [--no-appcast] [--no-plist]

Builds the GitHub Pages site into site:
  - the MkDocs site from docs/ (requires mkdocs)
  - the newest runtime-v release's WhiskyWineVersion.plist (requires gh);
    falls back to the deployed plist, or is absent if neither exists
  - DocC for WhiskyKit (requires macOS with Xcode)
  - the newest app release's appcast.xml (requires gh)

Options:
  --no-appcast  skip mirroring appcast.xml (offline/local builds)
  --no-plist    skip mirroring WhiskyWineVersion.plist (offline/local builds)
  -h, --help    show this help
EOF
}

SKIP_APPCAST=0
SKIP_PLIST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --no-appcast)
            SKIP_APPCAST=1
            ;;
        --no-plist)
            SKIP_PLIST=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="$PROJECT_DIR/site"
DOCC_DIR="$PROJECT_DIR/build/docc"
PACKAGE_DIR="$PROJECT_DIR/WhiskyKit"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: DocC builds require macOS with Xcode." >&2
    exit 1
fi

if ! command -v mkdocs >/dev/null 2>&1; then
    echo "error: mkdocs not found; install it with 'python3 -m pip install mkdocs==1.6.1 mkdocs-material==9.8.1'." >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "error: swift not found; install Xcode or the Swift toolchain." >&2
    exit 1
fi

if [ ! -f "$PROJECT_DIR/mkdocs.yml" ]; then
    echo "error: $PROJECT_DIR/mkdocs.yml not found." >&2
    exit 1
fi

if [ ! -f "$PROJECT_DIR/docs/index.md" ]; then
    echo "error: $PROJECT_DIR/docs/index.md not found." >&2
    exit 1
fi

if [ ! -f "$PACKAGE_DIR/Package.swift" ]; then
    echo "error: $PACKAGE_DIR/Package.swift not found." >&2
    exit 1
fi

warn() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::warning::$*"
    else
        echo "warning: $*" >&2
    fi
}

appcast_first_enclosure() {
    grep -o 'url="[^"]*"' "$1" | head -n 1 | cut -d'"' -f2
}

appcast_download_reachable() {
    local url="$1"
    [ -n "$url" ] || return 1
    case "$url" in
        https://*) ;;
        *) return 1 ;;
    esac
    if curl -fsIL --retry 3 --connect-timeout 15 "$url" >/dev/null 2>&1; then
        return 0
    fi
    curl -fsL --range 0-0 --retry 3 --connect-timeout 15 \
        -o /dev/null "$url" >/dev/null 2>&1
}

plist_is_valid() {
    local file="$1" sha
    plutil -lint "$file" >/dev/null 2>&1 || return 1
    sha="$(plutil -extract sha256 raw -o - "$file" 2>/dev/null || true)"
    sha="$(printf '%s' "$sha" | tr '[:upper:]' '[:lower:]')"
    printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$'
}

mirror_appcast() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "error: gh not found; install GitHub CLI or use --no-appcast." >&2
        exit 1
    fi

    if [ -z "${GH_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
        echo "error: gh is not authenticated; run 'gh auth login' or use --no-appcast." >&2
        exit 1
    fi

    local repo="${GITHUB_REPOSITORY:-}"
    if [ -z "$repo" ]; then
        repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    fi
    if [ -z "$repo" ]; then
        echo "error: could not determine repository; set GITHUB_REPOSITORY." >&2
        exit 1
    fi

    local owner="${repo%%/*}"
    local name="${repo#*/}"
    local feed_url="https://${owner}.github.io/${name}/appcast.xml"
    local tag

    tag="$(gh api "repos/${repo}/releases?per_page=100" \
        --jq '[.[] | select(.draft == false and .prerelease == false) | .tag_name | select(startswith("app-v"))][0] // ""')"

    rm -f "$SITE_DIR/appcast.xml"

    if [ -n "$tag" ] && gh release download "$tag" \
        --repo "$repo" \
        --pattern appcast.xml \
        --output "$SITE_DIR/appcast.xml"; then
        echo "Mirrored appcast.xml from release $tag"
        return
    fi

    # Fallback: reuse the deployed feed only when its newest download still
    # resolves, so a stale feed pointing at deleted releases is not mirrored.
    if curl -fsSL "$feed_url" --output "$SITE_DIR/appcast.xml"; then
        local enclosure
        enclosure="$(appcast_first_enclosure "$SITE_DIR/appcast.xml" || true)"
        if appcast_download_reachable "$enclosure"; then
            warn "could not read the newest app release's appcast.xml; reusing $feed_url"
            return
        fi
        rm -f "$SITE_DIR/appcast.xml"
        warn "deployed feed $feed_url has no reachable download; /appcast.xml will be absent"
    fi

    if [ -n "$tag" ]; then
        echo "error: latest app release $tag has no appcast.xml asset and no reachable deployed feed to reuse." >&2
        exit 1
    fi
    warn "no app releases or reachable deployed feed found; /appcast.xml will be absent"
}

mirror_plist() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "error: gh not found; install GitHub CLI or use --no-plist." >&2
        exit 1
    fi

    if [ -z "${GH_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
        echo "error: gh is not authenticated; run 'gh auth login' or use --no-plist." >&2
        exit 1
    fi

    local repo="${GITHUB_REPOSITORY:-}"
    if [ -z "$repo" ]; then
        repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    fi
    if [ -z "$repo" ]; then
        echo "error: could not determine repository; set GITHUB_REPOSITORY." >&2
        exit 1
    fi

    local owner="${repo%%/*}"
    local name="${repo#*/}"
    local plist_url="https://${owner}.github.io/${name}/WhiskyWineVersion.plist"
    local tag
    local tmp

    tag="$(gh api "repos/${repo}/releases?per_page=100" \
        --jq '[.[] | select(.draft == false and .prerelease == false) | select(.tag_name | startswith("runtime-v")) | select([.assets[].name] | index("WhiskyWineVersion.plist")) | .tag_name][0] // ""')"

    tmp="$(mktemp "${TMPDIR:-/tmp}/whisky-plist.XXXXXX")"

    if [ -n "$tag" ] && gh release download "$tag" \
        --repo "$repo" \
        --pattern WhiskyWineVersion.plist \
        --output "$tmp"; then
        if plist_is_valid "$tmp"; then
            cp "$tmp" "$SITE_DIR/WhiskyWineVersion.plist"
            rm -f "$tmp"
            echo "Mirrored WhiskyWineVersion.plist from release $tag"
            return
        fi
        warn "release $tag plist is invalid; trying the deployed plist"
    fi

    rm -f "$tmp"
    if curl -fsSL "$plist_url" --output "$tmp" && plist_is_valid "$tmp"; then
        cp "$tmp" "$SITE_DIR/WhiskyWineVersion.plist"
        rm -f "$tmp"
        warn "no usable runtime-v release; reusing $plist_url"
        return
    fi

    rm -f "$tmp"
    warn "no usable WhiskyWineVersion.plist source; /WhiskyWineVersion.plist will be absent"
}

cd "$PROJECT_DIR"

echo "==> Building MkDocs site"
mkdocs build --strict

if [ ! -f "$SITE_DIR/index.html" ]; then
    echo "error: MkDocs did not produce site/index.html." >&2
    exit 1
fi

echo "==> Building DocC for WhiskyKit"
rm -rf "$DOCC_DIR"
mkdir -p "$DOCC_DIR"
(
    cd "$PACKAGE_DIR"
    swift package \
        --scratch-path "$PROJECT_DIR/build/WhiskyKit" \
        --allow-writing-to-directory ../build/docc \
        generate-documentation \
        --target WhiskyKit \
        --disable-indexing \
        --transform-for-static-hosting \
        --hosting-base-path whisky \
        --output-path ../build/docc
)

if [ ! -f "$DOCC_DIR/documentation/whiskykit/index.html" ]; then
    echo "error: DocC did not produce documentation/whiskykit/index.html." >&2
    exit 1
fi

echo "==> Adding DocC output to the site"
shopt -s nullglob
for entry in "$DOCC_DIR"/*; do
    base=$(basename "$entry")
    case "$base" in
        index.html|sitemap.xml|robots.txt|404.html|favicon.ico)
            continue
            ;;
    esac
    rm -rf "${SITE_DIR:?}/$base"
    cp -R "$entry" "$SITE_DIR/"
done
shopt -u nullglob

if [ "$SKIP_PLIST" -eq 1 ]; then
    echo "==> Skipping plist mirror (--no-plist)"
else
    echo "==> Mirroring latest runtime release plist"
    mirror_plist
fi

if [ ! -f "$SITE_DIR/WhiskyWineVersion.plist" ]; then
    warn "/WhiskyWineVersion.plist will be absent (no runtime-v release asset and no deployed plist)"
fi

if [ "$SKIP_APPCAST" -eq 1 ]; then
    echo "==> Skipping appcast mirror (--no-appcast)"
else
    echo "==> Mirroring latest app release appcast"
    mirror_appcast
fi

echo
echo "Site artifact: $SITE_DIR"
ls -la "$SITE_DIR"
