#!/bin/bash
#
# clean.sh
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
# Removes local build products and caches:
#   - Xcode/SPM: build/, .build/, WhiskyKit/.build/, DerivedData/
#   - docs: site/
#   - runtime: scripts/runtime/build/, scripts/runtime/release/
#   - test/misc: *.xcresult, scripts/tests/WhiskyAudioTest.exe
#   - tool caches: __pycache__/, *.pyc
#
# With --all it also removes gitignored local-only directories:
#   .planning/, strix_runs/, plans/, .venv/, Pods/, Carthage/, Dependencies/,
#   .accio/, fastlane/test_output/, iOSInjectionProject/, .swiftpm/, and package leftovers.
#
# Usage: scripts/clean.sh [--dry-run] [--all]
#   --dry-run  Print what would be removed without deleting anything
#   --all      Also remove local-only caches and dependency-manager output
#   -h, --help Show this help

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)

DRY_RUN=0
ALL=0
REMOVED=0

usage() {
    cat <<'EOF'
Usage: scripts/clean.sh [--dry-run] [--all]

Options:
  --dry-run    Print what would be removed without deleting anything
  --all        Also remove local-only caches and dependency-manager output
  -h, --help   Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --all)
            ALL=1
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

remove_path() {
    local target="$1"
    [ -e "$target" ] || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'would remove %s\n' "$target"
    else
        printf 'removing %s\n' "$target"
        rm -rf -- "$target"
    fi
    REMOVED=$((REMOVED + 1))
}

remove_found() {
    local pattern="$1"
    while IFS= read -r -d '' entry; do
        remove_path "$entry"
    done < <(find "$PROJECT_DIR" \
        \( -path "$PROJECT_DIR/.git" -o -path "$PROJECT_DIR/site/node_modules" \) -prune -o \
        -name "$pattern" -print0 2>/dev/null)
}

# Build output
remove_path "$PROJECT_DIR/build"
remove_path "$PROJECT_DIR/.build"
remove_path "$PROJECT_DIR/WhiskyKit/.build"
remove_path "$PROJECT_DIR/site"
remove_path "$PROJECT_DIR/DerivedData"
remove_path "$PROJECT_DIR/scripts/runtime/build"
remove_path "$PROJECT_DIR/scripts/runtime/release"
remove_path "$PROJECT_DIR/scripts/tests/WhiskyAudioTest.exe"

# Tool caches
remove_found '__pycache__'
remove_found '*.pyc'
remove_found '*.xcresult'

# Local-only caches and dependency-manager output
if [ "$ALL" -eq 1 ]; then
    remove_path "$PROJECT_DIR/.planning"
    remove_path "$PROJECT_DIR/strix_runs"
    remove_path "$PROJECT_DIR/plans"
    remove_path "$PROJECT_DIR/.venv"
    remove_path "$PROJECT_DIR/Pods"
    remove_path "$PROJECT_DIR/Carthage"
    remove_path "$PROJECT_DIR/Dependencies"
    remove_path "$PROJECT_DIR/.accio"
    remove_path "$PROJECT_DIR/fastlane/test_output"
    remove_path "$PROJECT_DIR/iOSInjectionProject"
    remove_found '.swiftpm'
    remove_found '*.hmap'
    remove_found '*.dSYM'
    remove_found '*.dSYM.zip'
    remove_found '*.ipa'
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\nWould remove %d item(s).\n' "$REMOVED"
else
    printf '\nRemoved %d item(s).\n' "$REMOVED"
fi
