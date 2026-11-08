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
# Usage: scripts/build.sh [configuration] [scheme...]
# Example: scripts/build.sh Debug Whisky WhiskyCmd
#          scripts/build.sh Release Whisky

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
shift || true

SCHEMES=("$@")
if [ "${#SCHEMES[@]}" -eq 0 ]; then
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
