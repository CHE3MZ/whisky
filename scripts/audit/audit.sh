#!/bin/bash
#
# audit.sh
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
# Runs every audit script in this directory.
#
# audit_upstream.py needs the local (gitignored) .planning/milestones file, so it
# is skipped when that is absent. fill-missing-translations.py needs the Resources
# directory of a built app, so it is skipped when there is no Debug build.
#
# Usage: scripts/audit/audit.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

python3 "$SCRIPT_DIR/british-english.py" --check
python3 "$SCRIPT_DIR/check-placeholder-translations.py"

REQUIREMENTS="$REPO_ROOT/.planning/milestones/v1.0-REQUIREMENTS.md"
if [ -f "$REQUIREMENTS" ]; then
    python3 "$SCRIPT_DIR/audit_upstream.py"
else
    echo "skipping audit_upstream.py: no .planning/milestones/v1.0-REQUIREMENTS.md (local planning file)"
fi

RESOURCES="$REPO_ROOT/build/Build/Products/Debug/Whisky.app/Contents/Resources"
if [ -d "$RESOURCES" ]; then
    python3 "$SCRIPT_DIR/fill-missing-translations.py" --check "$RESOURCES"
else
    echo "skipping fill-missing-translations.py: no Debug build found, run 'task build' first"
fi
