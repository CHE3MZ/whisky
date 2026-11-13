#!/bin/sh
#
# pull.sh
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
# Applies the changes from one commit of the upstream Whisky repository
# (github.com/frankea/Whisky) to this working tree. Only that commit's patch,
# the files it needs, and their metadata are downloaded; nothing is cloned and
# no Git history is fetched. The patch is applied with git apply, temporary
# downloads are removed on exit, and the changes are left uncommitted so they
# can be reviewed before committing.
#
# Files that the commit changes but that do not exist in this working tree are
# restored from upstream at that commit, along with their file modes, so
# upstream-only files (such as CHANGELOG.md) are created instead of blocking
# the rest of the commit. Files that cannot be restored are skipped with a
# warning. If the GitHub CLI is authenticated, its token is used for the API
# request that reads file modes, avoiding the unauthenticated rate limit. If
# the patch does not apply cleanly, the script falls back to a partial apply
# and leaves conflicted hunks in *.rej files.
#
# Usage: scripts/upstream/pull.sh [-i COMMITSHA]
#   (no options)   Prompt for the commit SHA.
#   -i COMMITSHA   Apply COMMITSHA without prompting.
#   -h, --help     Show this help.
#
# Set NO_COLOR=1 to disable colors, or FORCE_COLOR=1 to keep them when piping.

set -eu
export LC_ALL=C

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(CDPATH='' cd "$SCRIPT_DIR/../.." && pwd)
UPSTREAM_REPO='frankea/Whisky'
COMMIT_SHA=''
COMMIT_SHORT=''
FULL_SHA=''
PATCH_FILE=''
APPLY_ERR=''
FILTERED_FILE=''
REJECT_OUT=''
DOWNLOAD_ERR=''
RAW_FILE=''
MISSING_LIST=''
RESTORED_LIST=''
SKIPPED_LIST=''
TREE_FILE=''
github_token=''
restored_count=0
skipped_count=0
TREE_READY=0
TREE_WARNED=0

RESET=''
BOLD=''
GREEN=''
WHITE=''
GRAY=''
RED=''
YELLOW=''
CYAN=''

if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; }; then
    RESET=$(printf '\033[0m')
    BOLD=$(printf '\033[1m')
    GREEN=$(printf '\033[32m')
    WHITE=$(printf '\033[37m')
    GRAY=$(printf '\033[90m')
    RED=$(printf '\033[31m')
    YELLOW=$(printf '\033[33m')
    CYAN=$(printf '\033[36m')
fi

usage() {
    cat <<'EOF'
Usage: scripts/upstream/pull.sh [-i COMMITSHA]

Applies the changes from one commit of github.com/frankea/Whisky to this
working tree without cloning the repository. Changes are left uncommitted.
Files the commit changes that are absent here are restored from upstream.

Options:
  -i COMMITSHA  Apply the given commit without prompting
  -h, --help    Show this help

Environment:
  NO_COLOR     Disable colored output
  FORCE_COLOR  Keep colors when output is piped
EOF
}

section() {
    printf '\n%s==>%s %s%s%s\n' "$CYAN$BOLD" "$RESET" "$BOLD$WHITE" "$*" "$RESET"
}

print_field() {
    printf '  %s%s:%s %s%s%s\n' "$GRAY" "$1" "$RESET" "$WHITE" "$2" "$RESET"
}

print_list() {
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '  %s%s%s\n' "$GRAY" "$line" "$RESET" >&2
    done
}

error() {
    printf '%s%serror:%s %s\n' "$RED" "$BOLD" "$RESET" "$*" >&2
}

warn() {
    printf '%s%swarning:%s %s\n' "$YELLOW" "$BOLD" "$RESET" "$*" >&2
}

note() {
    printf '%s%snote:%s %s\n' "$CYAN" "$BOLD" "$RESET" "$*" >&2
}

ok() {
    printf '%s%sdone:%s %s\n' "$GREEN" "$BOLD" "$RESET" "$*"
}

# shellcheck disable=SC2329
cleanup() {
    for file in "$PATCH_FILE" "$APPLY_ERR" "$FILTERED_FILE" "$REJECT_OUT" "$DOWNLOAD_ERR" \
        "$RAW_FILE" "$MISSING_LIST" "$RESTORED_LIST" "$SKIPPED_LIST" "$TREE_FILE"; do
        if [ -n "$file" ]; then
            rm -f "$file"
        fi
    done
}

new_temp() {
    mktemp "${TMPDIR:-/tmp}/whisky-upstream.XXXXXX"
}

trap 'cleanup' 0 1 2 3 15

while [ $# -gt 0 ]; do
    case "$1" in
        -i)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                error '-i requires a commit SHA'
                usage >&2
                exit 1
            fi
            COMMIT_SHA=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            error "unknown option: $1"
            usage >&2
            exit 1
            ;;
        *)
            error "unexpected argument: $1"
            usage >&2
            exit 1
            ;;
    esac
done

for tool in git curl mktemp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        error "$tool is required"
        exit 1
    fi
done

if command -v gh >/dev/null 2>&1; then
    github_token=$(gh auth token --hostname github.com 2>/dev/null) || github_token=''
    github_token=$(printf '%s' "$github_token" | tr -d '\r\n')
fi

cd "$PROJECT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "$PROJECT_DIR is not a Git working tree"
    exit 1
fi

if [ -n "$(git ls-files -u)" ]; then
    error 'the working tree has unresolved merge conflicts; resolve them first'
    exit 1
fi

printf '%s%sWhisky upstream pull%s\n' "$BOLD" "$WHITE" "$RESET"
print_field 'Upstream' "github.com/$UPSTREAM_REPO"

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')
if [ "$branch" = 'HEAD' ]; then
    branch="detached at $(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
fi
print_field 'Branch' "$branch"
if [ -n "$github_token" ]; then
    print_field 'API auth' 'GitHub CLI token'
else
    print_field 'API auth' 'unauthenticated'
fi

if [ -z "$COMMIT_SHA" ]; then
    if [ ! -t 0 ]; then
        error 'no commit SHA given and stdin is not interactive; use -i COMMITSHA'
        exit 1
    fi
    printf '\n%sCommit SHA from %s%s: ' "$BOLD" "$UPSTREAM_REPO" "$RESET"
    IFS= read -r COMMIT_SHA || COMMIT_SHA=''
fi

COMMIT_SHA=$(printf '%s' "$COMMIT_SHA" |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
    tr 'A-F' 'a-f')

if [ -z "$COMMIT_SHA" ]; then
    error 'a commit SHA is required'
    exit 1
fi

case "$COMMIT_SHA" in
    *[!0-9a-f]*)
        error "invalid commit SHA: $COMMIT_SHA"
        exit 1
        ;;
esac

sha_length=${#COMMIT_SHA}
if [ "$sha_length" -lt 7 ] || [ "$sha_length" -gt 40 ]; then
    error 'commit SHA must be 7-40 hexadecimal characters'
    exit 1
fi

COMMIT_SHORT=$(printf '%s' "$COMMIT_SHA" | cut -c1-12)

dirty_count=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')
if [ "$dirty_count" -gt 0 ]; then
    warn "the working tree has $dirty_count uncommitted file(s); the patch is applied on top of them"
fi

filter_patch() {
    awk -v skipped="$2" '
        BEGIN {
            count = split(skipped, paths, "\n")
            for (i = 1; i <= count; i++)
                skip[paths[i]] = 1
        }
        /^diff --(git|cc) / {
            path = $0
            if (path ~ /^diff --git /) {
                sub(/^diff --git a\//, "", path)
                sub(/ b\/.*/, "", path)
            } else {
                sub(/^diff --cc /, "", path)
            }
            skipping = (path in skip)
        }
        !skipping { print }
    ' "$1"
}

is_safe_path() {
    case "$1" in
        /*|..|../*|*/../*|*/..|-*|*\\*)
            return 1
            ;;
    esac
    return 0
}

rename_target_for() {
    awk -v target="$1" '
        /^diff --(git|cc) / {
            path = $0
            if (path ~ /^diff --git /) {
                sub(/^diff --git a\//, "", path)
                sub(/ b\/.*/, "", path)
            } else {
                sub(/^diff --cc /, "", path)
            }
            in_section = (path == target)
            next
        }
        in_section && /^rename to / {
            sub(/^rename to /, "")
            print
            exit
        }
    ' "$PATCH_FILE"
}

show_stat() {
    git apply --stat "$1" 2>/dev/null | sed 's/^/  /'
}

show_summary() {
    summary=$(git apply --numstat "$1" 2>/dev/null | awk '
        {
            files++
            if ($1 ~ /^[0-9]+$/) {
                added += $1
                removed += $2
            }
        }
        END { printf "%d file(s), +%d/-%d", files + 0, added + 0, removed + 0 }
    ')
    printf '  %s%s%s\n' "$GRAY" "$summary" "$RESET"
}

apply_patch() {
    if ! git apply "$1"; then
        error 'git apply failed; the working tree may be partially changed'
        exit 1
    fi
}

finish_success() {
    if [ "$skipped_count" -gt 0 ]; then
        warn "commit $COMMIT_SHORT is incomplete; $skipped_count absent file(s) were not restored"
        exit 1
    fi
    ok "$1"
    exit 0
}

make_temp() {
    temp_file=$(new_temp) || {
        error 'could not create a temporary file'
        exit 1
    }
    printf '%s' "$temp_file"
}

PATCH_FILE=$(make_temp)
APPLY_ERR=$(make_temp)
FILTERED_FILE=$(make_temp)
REJECT_OUT=$(make_temp)
DOWNLOAD_ERR=$(make_temp)
RAW_FILE=$(make_temp)
MISSING_LIST=$(make_temp)
RESTORED_LIST=$(make_temp)
SKIPPED_LIST=$(make_temp)
TREE_FILE=$(make_temp)

url="https://github.com/$UPSTREAM_REPO/commit/$COMMIT_SHA.patch"
section "Fetching $UPSTREAM_REPO@$COMMIT_SHORT"

download_status=0
http_code=$(curl -sSL --retry 3 --connect-timeout 15 --max-time 120 \
    -o "$PATCH_FILE" -w '%{http_code}' "$url" 2>"$DOWNLOAD_ERR") || download_status=$?

if [ "$download_status" -ne 0 ]; then
    error "could not reach GitHub (curl exit $download_status)"
    if [ -s "$DOWNLOAD_ERR" ]; then
        print_list < "$DOWNLOAD_ERR"
    fi
    exit 1
fi

case "$http_code" in
    200) ;;
    404)
        error "commit $COMMIT_SHORT was not found in $UPSTREAM_REPO"
        exit 1
        ;;
    *)
        error "GitHub returned HTTP $http_code for $url"
        if [ -s "$DOWNLOAD_ERR" ]; then
            print_list < "$DOWNLOAD_ERR"
        fi
        exit 1
        ;;
esac

if [ ! -s "$PATCH_FILE" ]; then
    error 'downloaded patch is empty'
    exit 1
fi

if ! head -n 1 "$PATCH_FILE" | grep -q '^From '; then
    error "GitHub did not return a patch for commit $COMMIT_SHORT"
    exit 1
fi

FULL_SHA=$(sed -n '1s/^From \([0-9a-fA-F]\{40\}\) .*/\1/p' "$PATCH_FILE")
if [ -z "$FULL_SHA" ]; then
    FULL_SHA=$COMMIT_SHA
fi

if ! grep -Eq '^diff --(git|cc) ' "$PATCH_FILE"; then
    finish_success "commit $COMMIT_SHORT has no file changes; nothing to apply"
fi

subject=$(sed -n '/^Subject: /,/^[[:space:]]*$/p' "$PATCH_FILE" |
    sed '1s/^Subject: //' |
    tr '\n' ' ' |
    sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//')
subject=$(printf '%s' "$subject" | sed 's/^\[PATCH[^]]*\] //')
author=$(sed -n 's/^From: //p' "$PATCH_FILE" | head -n 1)

if [ -n "$subject" ]; then
    print_field 'Subject' "$subject"
fi
if [ -n "$author" ]; then
    print_field 'Author' "$author"
fi

printf '\n'

if git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    finish_success "commit $COMMIT_SHORT is already applied; nothing to do"
fi

if git apply --check "$PATCH_FILE" 2>"$APPLY_ERR"; then
    show_stat "$PATCH_FILE"
    apply_patch "$PATCH_FILE"
    show_summary "$PATCH_FILE"
    finish_success "applied commit $COMMIT_SHORT"
fi

missing_files=$(sed -n 's/^error: \(.*\): No such file or directory$/\1/p' "$APPLY_ERR")
unexpected_errors=$(grep '^error: ' "$APPLY_ERR" | grep -v ': No such file or directory$' || true)
patch_to_apply=$PATCH_FILE

is_deleted_in_patch() {
    awk -v target="$1" '
        /^diff --(git|cc) / {
            path = $0
            if (path ~ /^diff --git /) {
                sub(/^diff --git a\//, "", path)
                sub(/ b\/.*/, "", path)
            } else {
                sub(/^diff --cc /, "", path)
            }
            in_section = (path == target)
        }
        in_section && /^deleted file mode / { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "$PATCH_FILE"
}

load_tree() {
    if [ "$TREE_READY" -eq 1 ]; then
        return 0
    fi
    if [ "$TREE_READY" -eq -1 ]; then
        return 1
    fi

    tree_url="https://api.github.com/repos/$UPSTREAM_REPO/git/trees/$FULL_SHA?recursive=1"
    tree_status=0
    if [ -n "$github_token" ]; then
        tree_code=$(printf 'header = "Authorization: Bearer %s"\n' "$github_token" |
            curl -sSL --retry 3 --connect-timeout 15 --max-time 120 \
                --config - \
                -H 'Accept: application/vnd.github+json' \
                -o "$TREE_FILE" -w '%{http_code}' "$tree_url" 2>/dev/null) || tree_status=$?
    else
        tree_code=$(curl -sSL --retry 3 --connect-timeout 15 --max-time 120 \
            -H 'Accept: application/vnd.github+json' \
            -o "$TREE_FILE" -w '%{http_code}' "$tree_url" 2>/dev/null) || tree_status=$?
    fi

    if [ "$tree_status" -ne 0 ] || [ "$tree_code" -ne 200 ] || [ ! -s "$TREE_FILE" ]; then
        TREE_READY=-1
        return 1
    fi

    TREE_READY=1
    return 0
}

mode_for_path() {
    awk -v target="$1" '
        /"path": "/ {
            line = $0
            sub(/.*"path": "/, "", line)
            sub(/".*/, "", line)
            current = line
            next
        }
        current == target && /"mode": "/ {
            line = $0
            sub(/.*"mode": "/, "", line)
            sub(/".*/, "", line)
            print line
            exit
        }
    ' "$TREE_FILE"
}

restore_missing_files() {
    : > "$RESTORED_LIST"
    : > "$SKIPPED_LIST"
    printf '%s\n' "$missing_files" > "$MISSING_LIST"

    while IFS= read -r path; do
        [ -n "$path" ] || continue

        if ! is_safe_path "$path"; then
            warn "refusing to restore unsafe path: $path"
            printf '%s\n' "$path" >> "$SKIPPED_LIST"
            continue
        fi

        rename_target=$(rename_target_for "$path")
        if [ -n "$rename_target" ]; then
            if [ -e "$rename_target" ] || [ -L "$rename_target" ]; then
                note "$rename_target already exists; leaving it unchanged"
                continue
            fi
            if ! is_safe_path "$rename_target"; then
                warn "refusing to restore unsafe path: $rename_target"
                printf '%s\n' "$rename_target" >> "$SKIPPED_LIST"
                continue
            fi
            path=$rename_target
        fi

        url_path=$(printf '%s' "$path" |
            sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/#/%23/g' -e 's/?/%3F/g')
        raw_url="https://raw.githubusercontent.com/$UPSTREAM_REPO/$FULL_SHA/$url_path"

        raw_status=0
        raw_code=$(curl -sSL --retry 3 --connect-timeout 15 --max-time 120 \
            -o "$RAW_FILE" -w '%{http_code}' "$raw_url" 2>/dev/null) || raw_status=$?

        if [ "$raw_status" -ne 0 ]; then
            warn "could not restore $path (curl exit $raw_status); skipping it"
            printf '%s\n' "$path" >> "$SKIPPED_LIST"
            continue
        fi

        case "$raw_code" in
            200)
                file_mode=''
                if load_tree; then
                    file_mode=$(mode_for_path "$path")
                fi
                if [ -z "$file_mode" ] && [ "$TREE_WARNED" -eq 0 ]; then
                    warn 'could not read file modes from GitHub; restored files will use mode 644'
                    TREE_WARNED=1
                fi

                case "$file_mode" in
                    120000|040000|160000)
                        warn "cannot restore $path: unsupported file mode $file_mode"
                        printf '%s\n' "$path" >> "$SKIPPED_LIST"
                        continue
                        ;;
                esac

                if [ "$file_mode" = '100755' ]; then
                    restore_mode=755
                else
                    restore_mode=644
                fi

                if ! mkdir -p "$(dirname "$path")"; then
                    warn "could not create the directory for $path; skipping it"
                    printf '%s\n' "$path" >> "$SKIPPED_LIST"
                elif mv -f "$RAW_FILE" "$path"; then
                    if chmod "$restore_mode" "$path"; then
                        printf '%s\n' "$path" >> "$RESTORED_LIST"
                    else
                        warn "could not set mode $restore_mode on $path; skipping it"
                        printf '%s\n' "$path" >> "$SKIPPED_LIST"
                    fi
                else
                    warn "could not write $path; skipping it"
                    printf '%s\n' "$path" >> "$SKIPPED_LIST"
                fi
                ;;
            404)
                if ! is_deleted_in_patch "$path"; then
                    warn "could not restore $path (HTTP 404); skipping it"
                    printf '%s\n' "$path" >> "$SKIPPED_LIST"
                fi
                ;;
            *)
                warn "could not restore $path (HTTP $raw_code); skipping it"
                printf '%s\n' "$path" >> "$SKIPPED_LIST"
                ;;
        esac
    done < "$MISSING_LIST"
}

report_restored() {
    restored_count=$(wc -l < "$RESTORED_LIST" | tr -d ' ')
    skipped_count=$(wc -l < "$SKIPPED_LIST" | tr -d ' ')

    if [ "$restored_count" -gt 0 ]; then
        note 'file(s) absent from this working tree; restored from upstream:'
        print_list < "$RESTORED_LIST"
    fi

    if [ "$skipped_count" -gt 0 ]; then
        warn 'file(s) absent from this working tree could not be restored; skipping:'
        print_list < "$SKIPPED_LIST"
    fi
}

if [ -n "$missing_files" ]; then
    restore_missing_files
    report_restored

    filter_patch "$PATCH_FILE" "$missing_files" > "$FILTERED_FILE"

    if ! grep -Eq '^diff --(git|cc) ' "$FILTERED_FILE"; then
        if [ "$restored_count" -gt 0 ]; then
            finish_success "applied commit $COMMIT_SHORT (restored absent files)"
        else
            finish_success 'nothing to apply; every changed file is absent from this working tree'
        fi
    fi

    if git apply --reverse --check "$FILTERED_FILE" >/dev/null 2>&1; then
        finish_success "commit $COMMIT_SHORT is already applied; nothing to do"
    fi

    if git apply --check "$FILTERED_FILE" 2>"$APPLY_ERR"; then
        show_stat "$FILTERED_FILE"
        apply_patch "$FILTERED_FILE"
        show_summary "$FILTERED_FILE"
        if [ "$restored_count" -gt 0 ]; then
            finish_success "applied commit $COMMIT_SHORT (restored absent files)"
        else
            finish_success "applied commit $COMMIT_SHORT"
        fi
    fi

    unexpected_errors=$(grep '^error: ' "$APPLY_ERR" | grep -v ': No such file or directory$' || true)
    patch_to_apply=$FILTERED_FILE
fi

if [ -n "$unexpected_errors" ]; then
    warn "commit $COMMIT_SHORT does not apply cleanly:"
    printf '%s\n' "$unexpected_errors" | print_list
fi

warn 'applying the remaining changes partially; rejected hunks are saved as *.rej files'

reject_status=0
git apply --reject "$patch_to_apply" >"$REJECT_OUT" 2>&1 || reject_status=$?

rejects=$(find . -name '*.rej' ! -path './.git/*' -newer "$PATCH_FILE" 2>/dev/null |
    sed 's#^\./##' | sort)

if [ -n "$rejects" ]; then
    warn 'some hunks could not be applied'
    grep -Ev '^(Checking patch|Applied patch .* cleanly\.)' "$REJECT_OUT" | print_list || true
    printf '  %sconflict file(s):%s\n' "$GRAY" "$RESET" >&2
    printf '%s\n' "$rejects" | print_list
    printf '  %sresolve each conflict, then delete the .rej file%s\n' "$GRAY" "$RESET" >&2
    exit 1
fi

if [ "$reject_status" -ne 0 ]; then
    error 'some changes could not be applied'
    grep -E '^(error:|warning:)' "$REJECT_OUT" | print_list || true
    printf '  %sresolve the conflicts before committing%s\n' "$GRAY" "$RESET" >&2
    exit 1
fi

show_stat "$patch_to_apply"
show_summary "$patch_to_apply"
finish_success "applied commit $COMMIT_SHORT"
