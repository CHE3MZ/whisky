#!/bin/sh
#
# pr.sh
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
# Opens the upstream-bump pull request against master in CHE3MZ/whisky. It refuses
# to run unless the current branch is exactly upstream-bump and it has commits
# that master does not, then reads the pinned frankea/Whisky commit from both
# branches' scripts/config/sources.yml. The pinned commit on master is reported
# as "last" and the one on upstream-bump as "final"; when they are identical the
# bump was already merged and the script aborts instead of opening an empty PR.
#
# The branch and its commits must already be pushed to origin, and local master
# must match origin/master so "last" is what the PR will actually merge into.
# An open pull request for the branch is reported instead of creating another.
#
# Usage: scripts/upstream/pr.sh [--help]
#
# Requires an authenticated gh CLI with access to the pull request repository.
#
# Set NO_COLOR=1 to disable colors, or FORCE_COLOR=1 to keep them when piping.

set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH='' cd "$SCRIPT_DIR/../.." && pwd)
PR_REPO='CHE3MZ/whisky'
BASE_BRANCH='master'
HEAD_BRANCH='upstream-bump'
SOURCES_PATH='scripts/config/sources.yml'

RESET=''
BOLD=''
GREEN=''
WHITE=''
GRAY=''
RED=''

if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; }; then
    RESET=$(printf '\033[0m')
    BOLD=$(printf '\033[1m')
    GREEN=$(printf '\033[32m')
    WHITE=$(printf '\033[37m')
    GRAY=$(printf '\033[90m')
    RED=$(printf '\033[31m')
fi

usage() {
    cat <<'EOF'
Usage: scripts/upstream/pr.sh

Opens a pull request from upstream-bump into master in CHE3MZ/whisky.

The current branch must be upstream-bump, it must have commits that master
does not, and its pinned frankea/Whisky commit in scripts/config/sources.yml
must differ from master's. The branch must already be pushed to origin, and
local master must match origin/master. An open pull request for the branch is
reported instead of creating another.

Environment:
  NO_COLOR     Disable colored output
  FORCE_COLOR  Keep colors when output is piped
EOF
}

error() {
    printf '%s%serror:%s %s\n' "$RED" "$BOLD" "$RESET" "$*" >&2
}

ok() {
    printf '%s%sdone:%s %s\n' "$GREEN" "$BOLD" "$RESET" "$*"
}

print_field() {
    printf '  %s%s:%s %s%s%s\n' "$GRAY" "$1" "$RESET" "$WHITE" "$2" "$RESET"
}

case "${1:-}" in
    '')
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        error "unknown argument: $1"
        usage >&2
        exit 1
        ;;
esac

for tool in git gh; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        error "$tool is required"
        exit 1
    fi
done

cd "$PROJECT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "$PROJECT_DIR is not a Git working tree"
    exit 1
fi

current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || current_branch=''
if [ "$current_branch" != "$HEAD_BRANCH" ]; then
    error "current branch is '${current_branch:-detached HEAD}', expected '$HEAD_BRANCH'"
    exit 1
fi

if ! git rev-parse --verify --quiet "refs/heads/$BASE_BRANCH" >/dev/null; then
    error "local branch '$BASE_BRANCH' not found"
    exit 1
fi

# "last" is read from master, so master must be what the PR will merge into.
if origin_base=$(git rev-parse --verify --quiet "refs/remotes/origin/$BASE_BRANCH"); then
    if [ "$(git rev-parse --verify "$BASE_BRANCH")" != "$origin_base" ]; then
        error "local $BASE_BRANCH does not match origin/$BASE_BRANCH; fetch and update it first"
        exit 1
    fi
fi

if ! ahead=$(git rev-list --count "$BASE_BRANCH..$HEAD_BRANCH" 2>/dev/null); then
    error "could not compare $HEAD_BRANCH with $BASE_BRANCH"
    exit 1
fi
if [ "$ahead" -eq 0 ]; then
    error "$HEAD_BRANCH has no new commits over $BASE_BRANCH"
    exit 1
fi

# Prints the commit pinned for the frankea/Whisky source (id UPSTREAM).
upstream_commit() {
    git show "$1:$SOURCES_PATH" 2>/dev/null | tr -d '\r' | awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function scalar(s) {
            s = trim(s)
            if (s ~ /^".*"$/ || s ~ /^'\''.*'\''$/)
                s = substr(s, 2, length(s) - 2)
            if (s == "null" || s == "~")
                s = ""
            return s
        }
        /^[ \t]*-[ \t]+/ {
            in_upstream = 0
            line = $0
            sub(/^[ \t]*-[ \t]+/, "", line)
            key = line
            sub(/:.*/, "", key)
            if (trim(key) == "id") {
                value = line
                sub(/^[^:]*:[ \t]*/, "", value)
                in_upstream = (scalar(value) == "UPSTREAM")
            }
            next
        }
        /^[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*:/ {
            line = $0
            sub(/^[ \t]+/, "", line)
            key = line
            sub(/:.*/, "", key)
            key = trim(key)
            if (key == "id") {
                value = line
                sub(/^[^:]*:[ \t]*/, "", value)
                in_upstream = (scalar(value) == "UPSTREAM")
            } else if (key == "commit" && in_upstream) {
                value = line
                sub(/^[^:]*:[ \t]*/, "", value)
                print scalar(value)
                exit
            }
            next
        }
    '
}

validate_sha() {
    sha=$1
    ref=$2

    case "$sha" in
        *[!0-9a-fA-F]*)
            error "invalid frankea/Whisky commit in $ref:$SOURCES_PATH: $sha"
            return 1
            ;;
    esac
    if [ "${#sha}" -lt 7 ] || [ "${#sha}" -gt 40 ]; then
        error "frankea/Whisky commit in $ref:$SOURCES_PATH must be 7-40 hexadecimal characters: $sha"
        return 1
    fi
}

last_sha=$(upstream_commit "$BASE_BRANCH" | head -n 1)
if [ -z "$last_sha" ]; then
    error "could not read the frankea/Whisky commit from $BASE_BRANCH:$SOURCES_PATH"
    exit 1
fi
validate_sha "$last_sha" "$BASE_BRANCH" || exit 1

final_sha=$(upstream_commit "$HEAD_BRANCH" | head -n 1)
if [ -z "$final_sha" ]; then
    error "could not read the frankea/Whisky commit from $HEAD_BRANCH:$SOURCES_PATH"
    exit 1
fi
validate_sha "$final_sha" "$HEAD_BRANCH" || exit 1

last_sha=$(printf '%s' "$last_sha" | tr 'A-F' 'a-f')
final_sha=$(printf '%s' "$final_sha" | tr 'A-F' 'a-f')

if [ "$final_sha" = "$last_sha" ]; then
    error "$HEAD_BRANCH pins the same frankea/Whisky commit as $BASE_BRANCH ($last_sha); nothing to open"
    exit 1
fi

last_short=$(printf '%s' "$last_sha" | cut -c1-12)
final_short=$(printf '%s' "$final_sha" | cut -c1-12)

if ! gh auth status >/dev/null 2>&1; then
    error 'gh is not authenticated; run "gh auth login"'
    exit 1
fi

if ! gh repo view "$PR_REPO" --json nameWithOwner >/dev/null 2>&1; then
    error "pull request repository $PR_REPO does not exist or is not accessible"
    exit 1
fi

if remote_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/$HEAD_BRANCH"); then
    if [ "$remote_sha" != "$(git rev-parse HEAD)" ]; then
        error "local $HEAD_BRANCH does not match origin/$HEAD_BRANCH; push or pull to sync it first"
        exit 1
    fi
else
    error "origin/$HEAD_BRANCH not found; run 'git push -u origin $HEAD_BRANCH' first"
    exit 1
fi

title="upstream: pulled changes from upstream repo, last: $last_short, final: $final_short"
body="### pulled changes from upstream
**last:** $last_short
**final:** $final_short"

printf '%s%sWhisky upstream pull request%s\n' "$BOLD" "$WHITE" "$RESET"
print_field 'Repository' "$PR_REPO"
print_field 'Branch' "$HEAD_BRANCH"
print_field 'Base' "$BASE_BRANCH"
print_field 'Commits' "$ahead"
print_field 'Last' "$last_short"
print_field 'Final' "$final_short"
printf '\n'

if ! existing_pr=$(gh pr list --repo "$PR_REPO" --head "$HEAD_BRANCH" --state open \
    --json url --jq '.[0].url // empty' 2>/dev/null); then
    error "could not check for an open pull request in $PR_REPO"
    exit 1
fi
if [ -n "$existing_pr" ]; then
    printf '  %s%spull request already open:%s %s%s%s\n' \
        "$GRAY" "$BOLD" "$RESET" "$WHITE" "$existing_pr" "$RESET"
    exit 0
fi

if pr_url=$(gh pr create --repo "$PR_REPO" --base "$BASE_BRANCH" --head "$HEAD_BRANCH" \
    --title "$title" --body "$body"); then
    ok "pull request created: $pr_url"
else
    error 'could not create the pull request'
    exit 1
fi
