#!/bin/bash
#
# build.sh
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
# Builds the app with xcodebuild, keeping all derived data inside the repository's
# build/ directory instead of ~/Library/Developer/Xcode/DerivedData.
#
# Usage: scripts/build.sh [--full] [configuration] [scheme...]
# Example: scripts/build.sh                       # Debug Whisky
#          scripts/build.sh --full                # Debug Whisky WhiskyCmd WhiskyThumbnail
#          scripts/build.sh Release Whisky        # Release Whisky
#          scripts/build.sh Debug Whisky WhiskyCmd

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build.sh [--full] [configuration] [scheme...]

Options:
  --full       Build every scheme (Whisky, WhiskyCmd, WhiskyThumbnail)
  -h, --help   Show this help

Defaults to the Whisky scheme in Debug when no scheme is given.
EOF
}

FULL=0
POSITIONAL=()

while [ $# -gt 0 ]; do
    case "$1" in
        --full)
            FULL=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            printf 'error: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${POSITIONAL[0]:-Debug}"

if [ "$FULL" -eq 1 ]; then
    SCHEMES=(Whisky WhiskyCmd WhiskyThumbnail)
elif [ "${#POSITIONAL[@]}" -gt 1 ]; then
    SCHEMES=("${POSITIONAL[@]:1}")
else
    SCHEMES=(Whisky)
fi

cd "$PROJECT_DIR"

for scheme in "${SCHEMES[@]}"; do
    echo "==> Building $scheme ($CONFIGURATION)"
    xcodebuild \
        -project Whisky.xcodeproj \
        -scheme "$scheme" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath build \
        build
done
