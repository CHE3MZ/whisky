#!/bin/bash
#
# tag.sh
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
# Bumps the patch version of the newest runtime-vX.Y.Z tag and pushes it. The push
# triggers .github/workflows/Runtime.yml, which builds and publishes the runtime.
#
# The base version is the newest local runtime-vX.Y.Z tag. On a fresh repo with no
# runtime tags it falls back to the version in docs/WhiskyWineVersion.plist, so the
# first tag is that version with the patch bumped.
#
# Requires a clean working tree (no staged, unstaged, or untracked changes).
#
# Usage: scripts/runtime/tag.sh [--dry-run]
#   --dry-run    Print the next tag without creating or pushing it
#   -h, --help   Show this help

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH='' cd "$SCRIPT_DIR/../.." && pwd)
PLIST="$PROJECT_DIR/docs/WhiskyWineVersion.plist"

DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: scripts/runtime/tag.sh [--dry-run]

Bumps the patch version of the newest runtime-vX.Y.Z tag and pushes it.

Options:
  --dry-run    Print the next tag without creating or pushing it
  -h, --help   Show this help
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

plist_version() {
    if command -v plutil >/dev/null 2>&1; then
        printf '%s.%s.%s\n' \
            "$(plutil -extract version.major raw -o - "$PLIST")" \
            "$(plutil -extract version.minor raw -o - "$PLIST")" \
            "$(plutil -extract version.patch raw -o - "$PLIST")"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    version = plistlib.load(handle).get("version") or {}
print("{}.{}.{}".format(version.get("major", 0), version.get("minor", 0), version.get("patch", 0)))
PY
    else
        awk '
            index($0, "<key>major</key>") { getline; gsub(/[^0-9]/, "", $0); major = $0 }
            index($0, "<key>minor</key>") { getline; gsub(/[^0-9]/, "", $0); minor = $0 }
            index($0, "<key>patch</key>") { getline; gsub(/[^0-9]/, "", $0); patch = $0 }
            END { print major "." minor "." patch }
        ' "$PLIST"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
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

command -v git >/dev/null 2>&1 || die "git is required"
[ -f "$PLIST" ] || die "$PLIST not found"

if [ "$DRY_RUN" -eq 0 ]; then
    if [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]; then
        echo "error: working tree is dirty; commit or stash first." >&2
        git -C "$PROJECT_DIR" status --short >&2
        exit 1
    fi
    git -C "$PROJECT_DIR" fetch --tags --quiet
fi

current_tag=$(git -C "$PROJECT_DIR" tag -l 'runtime-v*' --sort=-version:refname | head -n 1)
if [ -n "$current_tag" ]; then
    current="${current_tag#runtime-v}"
    base_source="tag $current_tag"
else
    current="$(plist_version)"
    base_source="docs/WhiskyWineVersion.plist"
fi

case "$current" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) die "could not determine a valid current runtime version (got '$current')" ;;
esac

IFS='.' read -r major minor patch <<< "$current"
next="$major.$minor.$((10#$patch + 1))"
tag="runtime-v$next"

if git -C "$PROJECT_DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    die "tag $tag already exists"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'would tag %s (base %s from %s)\n' "$tag" "$current" "$base_source"
    exit 0
fi

git -C "$PROJECT_DIR" tag -a "$tag" -m "Wine Libraries v$next"
git -C "$PROJECT_DIR" push origin "$tag"

printf '\nTagged %s (base %s from %s).\n' "$tag" "$current" "$base_source"
printf 'Runtime.yml will build and publish the release. Once it finishes, update the plist:\n'
printf '  gh release download %s --pattern Libraries.tar.gz\n' "$tag"
printf '  bash scripts/runtime/sync.sh --archive Libraries.tar.gz\n'
