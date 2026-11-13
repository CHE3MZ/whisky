#!/bin/sh
#
# track.sh
#
# Checks each source in sources.yml against GitHub:
#   - commit:  compared with the latest commit on the repository's default branch
#   - release: compared with the tag from the repository's latest GitHub release
#
# With --github, a changed source opens an issue with the gh CLI in ISSUE_REPO.
#
# Usage: scripts/upstream/track.sh [--github] [SOURCES_YML]
#
# Set GITHUB_TOKEN (or GH_TOKEN) to raise the GitHub API rate limit.
# When no environment token is set, the gh CLI token is used if available.
# Set NO_COLOR=1 to disable colors, or FORCE_COLOR=1 to keep them when piping.
# Exits 0 when all lookups succeed (even if changes are found), 1 on errors.

set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
GITHUB_ISSUES=0
SOURCES_FILE=''
ISSUE_REPO='CHE3MZ/whisky'
TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}
SEP=$(printf '\034')

RESET=''
BOLD=''
GREEN=''
WHITE=''
GRAY=''
RED=''
YELLOW=''

if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; }; then
    RESET=$(printf '\033[0m')
    BOLD=$(printf '\033[1m')
    GREEN=$(printf '\033[32m')
    WHITE=$(printf '\033[37m')
    GRAY=$(printf '\033[90m')
    RED=$(printf '\033[31m')
    YELLOW=$(printf '\033[33m')
fi

usage() {
    cat <<'EOF'
Usage: scripts/upstream/track.sh [--github] [SOURCES_YML]

Checks sources in sources.yml against GitHub.

Options:
  --github    Create an issue in the ISSUE_REPO when a source has a new
              commit or release (requires gh)
  -h, --help  Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --github)
            GITHUB_ISSUES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if [ $# -gt 0 ]; then
                SOURCES_FILE=$1
                shift
            fi
            break
            ;;
        -*)
            printf 'error: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            if [ -n "$SOURCES_FILE" ]; then
                printf 'error: unexpected argument: %s\n' "$1" >&2
                exit 1
            fi
            SOURCES_FILE=$1
            shift
            ;;
    esac
done

SOURCES_FILE=${SOURCES_FILE:-"$SCRIPT_DIR/../config/sources.yml"}

print_field() {
    printf '  %s%s:%s %s%s%s\n' "$GRAY" "$1" "$RESET" "$WHITE" "$2" "$RESET"
}

print_ok() {
    printf '  %s%sno changes on source%s\n' "$GREEN" "$BOLD" "$RESET"
}

print_changes() {
    printf '  %s%schanges found!%s %snew %s:%s %s%s%s\n' \
        "$YELLOW" "$BOLD" "$RESET" \
        "$WHITE" "$1" "$RESET" \
        "$BOLD$WHITE" "$2" "$RESET"
}

print_error() {
    printf '  %s%serror:%s %s%s%s\n' "$RED" "$BOLD" "$RESET" "$RED" "$1" "$RESET"
}

if ! command -v curl >/dev/null 2>&1; then
    printf '%s%serror:%s curl is required\n' "$RED" "$BOLD" "$RESET" >&2
    exit 1
fi

if [ -z "$TOKEN" ] && command -v gh >/dev/null 2>&1; then
    TOKEN=$(gh auth token --hostname github.com 2>/dev/null || true)
    TOKEN=$(printf '%s' "$TOKEN" | tr -d '\r\n')
fi

if [ "$GITHUB_ISSUES" -eq 1 ]; then
    if ! command -v gh >/dev/null 2>&1; then
        printf '%s%serror:%s the gh CLI is required for --github\n' \
            "$RED" "$BOLD" "$RESET" >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        printf '%s%serror:%s gh is not authenticated; run "gh auth login"\n' \
            "$RED" "$BOLD" "$RESET" >&2
        exit 1
    fi
    if ! gh repo view "$ISSUE_REPO" --json nameWithOwner >/dev/null 2>&1; then
        printf '%s%serror:%s issue repository %s does not exist or is not accessible\n' \
            "$RED" "$BOLD" "$RESET" "$ISSUE_REPO" >&2
        exit 1
    fi
fi

if [ ! -f "$SOURCES_FILE" ]; then
    printf '%s%serror:%s sources file not found: %s\n' \
        "$RED" "$BOLD" "$RESET" "$SOURCES_FILE" >&2
    exit 1
fi

api_curl() {
    if [ -n "$TOKEN" ]; then
        printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" |
            curl --config - --connect-timeout 15 --max-time 30 \
                -H "Accept: application/vnd.github+json" \
                -H "User-Agent: whisky-source-check" \
                "$@"
    else
        curl --connect-timeout 15 --max-time 30 \
            -H "Accept: application/vnd.github+json" \
            -H "User-Agent: whisky-source-check" \
            "$@"
    fi
}

api_get() {
    api_curl -fsSL "$1"
}

api_status() {
    status_line=$(api_curl -sSL -w '\n%{http_code}' "$1" 2>/dev/null | tail -n 1)
    case "$status_line" in
        [0-9][0-9][0-9]) printf '%s\n' "$status_line" ;;
        *) return 1 ;;
    esac
}

validate_pin() {
    pin_url=$1
    pin_label=$2

    if ! pin_status=$(api_status "$pin_url" 2>/dev/null); then
        print_error "could not reach GitHub while validating $pin_label"
        return 1
    fi

    case "$pin_status" in
        200|204) return 0 ;;
        000)
            print_error "could not reach GitHub while validating $pin_label"
            ;;
        404|422)
            print_error "$pin_label was not found"
            ;;
        401|403)
            print_error "GitHub refused the request while validating $pin_label (check the token or rate limit)"
            ;;
        *)
            print_error "GitHub returned HTTP $pin_status while validating $pin_label"
            ;;
    esac
    return 1
}

parse_sources() {
    tr -d '\r' < "$1" | awk '
        function trim(s) {
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            return s
        }
        function scalar(s) {
            s = trim(s)
            if (s ~ /^".*"$/ || s ~ /^'\''.*'\''$/)
                s = substr(s, 2, length(s) - 2)
            if (s == "null" || s == "~")
                s = ""
            return s
        }
        function set_field(line,    key, value) {
            key = line
            sub(/:.*/, "", key)
            value = line
            sub(/^[^:]*:[ \t]*/, "", value)
            key = trim(key)
            if (key == "name")
                name = scalar(value)
            else if (key == "link")
                link = scalar(value)
            else if (key == "commit")
                commit = scalar(value)
            else if (key == "release")
                release = scalar(value)
        }
        function emit() {
            if (active)
                printf "%s\034%s\034%s\034%s\034%s\n", section, name, link, commit, release
            active = 0
            name = link = commit = release = ""
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

latest_commit_sha() {
    tr ',' '\n' |
        sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]\{40\}\)".*/\1/p' |
        head -n 1
}

latest_release_tag() {
    tr ',' '\n' |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1
}

normalize_version() {
    printf '%s' "$1" | sed 's/^[vV]\([0-9]\)/\1/'
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

issue_exists() {
    if ! issue_titles=$(gh issue list --repo "$1" --state all \
        --search "$2 in:title" --json title --jq '.[].title' 2>/dev/null); then
        return 2
    fi
    printf '%s\n' "$issue_titles" | grep -Fqx "$2"
}

create_issue() {
    issue_repo=$1
    issue_title=$2
    issue_body=$3

    issue_status=0
    issue_exists "$issue_repo" "$issue_title" || issue_status=$?
    if [ "$issue_status" -eq 2 ]; then
        print_error "could not check existing issues in $issue_repo"
        return 1
    elif [ "$issue_status" -eq 0 ]; then
        printf '  %s%sissue already exists:%s %s%s%s\n' \
            "$GRAY" "$BOLD" "$RESET" "$WHITE" "$issue_repo" "$RESET"
        return 0
    fi

    if issue_url=$(gh issue create --repo "$issue_repo" \
        --title "$issue_title" --body "$issue_body" 2>/dev/null); then
        printf '  %s%sissue created:%s %s%s%s\n' \
            "$GREEN" "$BOLD" "$RESET" "$WHITE" "$issue_url" "$RESET"
    else
        print_error "could not create issue in $issue_repo (check gh auth and permissions)"
        return 1
    fi
}

report_update() {
    update_name=$1
    update_link=$2
    update_kind=$3
    update_old=$4
    update_new=$5
    update_subject=$6

    [ "$GITHUB_ISSUES" -eq 1 ] || return 0

    update_title="Update ${update_name} to ${update_subject}"
    update_body=$(printf "A new %s is available for %s.\n\n- Source: %s\n- Pinned %s: \`%s\`\n- Latest %s: \`%s\`\n\nUpdate the pinned value in \`scripts/config/sources.yml\`.\n" \
        "$update_kind" "$update_name" "$update_link" \
        "$update_kind" "$update_old" "$update_kind" "$update_new")

    create_issue "$ISSUE_REPO" "$update_title" "$update_body" || source_error=1
}

tmp=$(mktemp "${TMPDIR:-/tmp}/whisky-sources.XXXXXX")
trap 'rm -f "$tmp"' 0 1 2 3 15

parse_sources "$SOURCES_FILE" > "$tmp"

if [ ! -s "$tmp" ]; then
    printf '%s%serror:%s no sources found in %s\n' \
        "$RED" "$BOLD" "$RESET" "$SOURCES_FILE" >&2
    exit 1
fi

printf '%s\n' "${BOLD}${WHITE}Whisky source tracker${RESET}"
printf '%s\n\n' "${GRAY}Checking ${SOURCES_FILE}${RESET}"

total=0
up_to_date=0
with_changes=0
errors=0

source_count=$(awk -F"$SEP" '$1 == "sources" { n++ } END { print n + 0 }' "$tmp")
if [ "$source_count" -eq 0 ]; then
    printf '%s%serror:%s no sources found in %s\n' \
        "$RED" "$BOLD" "$RESET" "$SOURCES_FILE" >&2
    exit 1
fi

while IFS="$SEP" read -r section name link commit release; do
    [ "$section" = "sources" ] || continue
    total=$((total + 1))

    if [ -z "$link" ]; then
        print_error "source '$name' has no link, skipping"
        errors=$((errors + 1))
        printf '\n'
        continue
    fi

    [ -n "$name" ] || name=$link

    printf '%s %s\n' \
        "${BOLD}${WHITE}${name}${RESET}" \
        "${GRAY}(${link})${RESET}"

    if ! repo_slug=$(github_slug "$link"); then
        print_error "could not parse a GitHub repository from $link, skipping"
        errors=$((errors + 1))
        printf '\n'
        continue
    fi

    source_changed=0
    source_error=0

    if [ -z "$commit" ] && [ -z "$release" ]; then
        print_error "source '$name' has neither a commit nor a release"
        source_error=1
    fi

    if [ -n "$commit" ]; then
        print_field "pinned commit" "$commit"
        if ! validate_pin "https://api.github.com/repos/$repo_slug/commits/$commit" "pinned commit $commit in $repo_slug"; then
            source_error=1
        elif body=$(api_get "https://api.github.com/repos/$repo_slug/commits?per_page=1" 2>/dev/null); then
            latest=$(printf '%s\n' "$body" | latest_commit_sha)
            if [ -z "$latest" ]; then
                print_error "could not read the latest commit from GitHub"
                source_error=1
            else
                pinned=$(printf '%s' "$commit" | tr 'A-F' 'a-f')
                latest_lc=$(printf '%s' "$latest" | tr 'A-F' 'a-f')
                print_field "latest commit" "$latest"
                case "$latest_lc" in
                    "$pinned"*)
                        print_ok
                        ;;
                    *)
                        print_changes "commit ID" "$latest"
                        short_commit=$(printf '%s' "$latest" | cut -c1-12)
                        report_update "$name" "$link" "commit" "$commit" "$latest" "commit $short_commit"
                        source_changed=1
                        ;;
                esac
            fi
        else
            print_error "could not query GitHub for $repo_slug (repository missing, no commits, or API rate limit)"
            source_error=1
        fi
    fi

    if [ -n "$release" ]; then
        print_field "pinned release" "$release"
        if ! validate_pin "https://api.github.com/repos/$repo_slug/releases/tags/$release" "pinned release $release in $repo_slug"; then
            source_error=1
        elif body=$(api_get "https://api.github.com/repos/$repo_slug/releases/latest" 2>/dev/null); then
            tag=$(printf '%s\n' "$body" | latest_release_tag)
            if [ -z "$tag" ]; then
                print_error "could not read the latest release tag from GitHub"
                source_error=1
            else
                pinned=$(normalize_version "$release")
                latest_version=$(normalize_version "$tag")
                print_field "latest release" "$tag"
                if [ "$pinned" = "$latest_version" ]; then
                    print_ok
                else
                    print_changes "release tag" "$tag"
                    report_update "$name" "$link" "release" "$release" "$tag" "$tag"
                    source_changed=1
                fi
            fi
        else
            print_error "could not find a GitHub release for $repo_slug (or API rate limit)"
            source_error=1
        fi
    fi

    if [ "$source_error" -ne 0 ]; then
        errors=$((errors + 1))
    elif [ "$source_changed" -ne 0 ]; then
        with_changes=$((with_changes + 1))
    else
        up_to_date=$((up_to_date + 1))
    fi
    printf '\n'
done < "$tmp"

printf '%s\n' "${GRAY}------------------------------------------------------------${RESET}"
printf '%s%s%s checked: %s%s up to date%s, %s%s with changes%s, %s%s error(s)%s\n' \
    "$BOLD$WHITE" "$total" "$RESET" \
    "$GREEN" "$up_to_date" "$RESET" \
    "$YELLOW" "$with_changes" "$RESET" \
    "$RED" "$errors" "$RESET"

if [ "$errors" -gt 0 ]; then
    exit 1
fi
exit 0
