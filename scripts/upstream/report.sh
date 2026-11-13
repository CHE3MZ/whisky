#!/bin/sh
#
# report.sh
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
# Regenerates docs/misc/dependencies.md from the pins in
# scripts/config/sources.yml.
#
# The document describes what each bundled component does and how they fit
# together; the pinned versions are read from sources.yml so the doc ages with
# the pins instead of in prose. Run it after changing a pin.
#
# The prose (descriptions and the "how they connect" section) lives in this
# script, keyed by each source's `id` field. Add a source to sources.yml and a
# matching case here, or it is listed with a generic description. Sources that
# are not part of the runtime stack (such as the Sparkle app updater) are
# skipped by documents_source().
#
# Usage: scripts/upstream/report.sh [--check] [OUTPUT_MD]

set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SOURCES_FILE=${SOURCES_FILE:-"$SCRIPT_DIR/../config/sources.yml"}
OUTPUT_FILE=''
CHECK=0
SEP=$(printf '\034')

usage() {
    cat <<'EOF'
Usage: scripts/upstream/report.sh [--check] [OUTPUT_MD]

Regenerates docs/misc/dependencies.md from the pins in sources.yml.

Options:
  --check     Exit 1 if OUTPUT_MD is out of date instead of writing it
  -h, --help  Show this help

Environment:
  SOURCES_FILE  Pin list to read (default: scripts/config/sources.yml)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            CHECK=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            printf 'error: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            if [ -n "$OUTPUT_FILE" ]; then
                printf 'error: unexpected argument: %s\n' "$1" >&2
                exit 1
            fi
            OUTPUT_FILE=$1
            ;;
    esac
    shift
done

OUTPUT_FILE=${OUTPUT_FILE:-"$SCRIPT_DIR/../../docs/misc/dependencies.md"}

if [ ! -f "$SOURCES_FILE" ]; then
    printf 'error: sources file not found: %s\n' "$SOURCES_FILE" >&2
    exit 1
fi

# Emits "<id>\034<name>\034<link>\034<commit>\034<release>" per source entry.
parse_sources() {
    tr -d '\r' < "$1" | awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function scalar(s) {
            s = trim(s)
            if (s ~ /^".*"$/ || s ~ /^'\''.*'\''$/) s = substr(s, 2, length(s) - 2)
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
            else if (key == "name")
                name = scalar(value)
            else if (key == "link")
                link = scalar(value)
            else if (key == "commit")
                commit = scalar(value)
            else if (key == "release")
                release = scalar(value)
        }
        function emit() {
            if (active && section == "sources")
                printf "%s\034%s\034%s\034%s\034%s\n", id, name, link, commit, release
            active = 0
            id = name = link = commit = release = ""
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

# App-only sources are tracked in sources.yml so track.sh sees new releases,
# but they are not part of the runtime stack this document describes.
documents_source() {
    case "$1" in
        SPARKLE) return 1 ;;
    esac
    return 0
}

# Prints the "### name + description" block for one source, keyed by id.
component_description() {
    case "$1" in
UPSTREAM) cat <<'EOF'
### Whisky upstream — the project this fork tracks

The upstream Whisky project. Its commit is pinned so app-level changes (bug fixes, UI, bottle
handling) are reviewed and merged deliberately instead of drifting in. It is the codebase this fork
is built from, tracked alongside the runtime binaries so movement in either shows up in one place.
EOF
            ;;
        WINE) cat <<'EOF'
### Wine — the Windows runtime

Wine implements the Windows API so Windows `.exe`/`.dll` binaries run natively on macOS without a
virtual machine. Whisky ships Gcenx's macOS build of Wine as `Libraries/Wine/`, and every bottle
runs inside it. DXVK and DXMT replace its Direct3D translation, MoltenVK and msync extend its
graphics and synchronization layers, and winetricks installs Windows components into a bottle's
Wine prefix.
EOF
            ;;
        DXVK) cat <<'EOF'
### DXVK (macOS) — Direct3D 9/10/11 → Vulkan

DXVK translates Direct3D 9/10/11 calls into Vulkan; on macOS that Vulkan comes from MoltenVK, so the
chain runs Direct3D → DXVK → MoltenVK → Metal. It is the default rendering backend for most games
and is selected per bottle.

The 1.10.x line is frozen on purpose: the 2.x series needs Vulkan 1.3 extensions MoltenVK/macOS do
not expose, so an upstream 2.x release is not a reason to bump it.
EOF
            ;;
        DXMT) cat <<'EOF'
### DXMT — Direct3D 11 → Metal

DXMT translates Direct3D 11 straight to Metal and is selectable per bottle as an alternative to DXVK
for D3D11 titles. Whisky strips Wine's "builtin DLL" marker from the DXMT trio so it loads as native,
and pairs it with Wine's `winemetal` shim.
EOF
            ;;
        *)
            printf '### %s\n\nTracked at <%s>.\n' "$2" "$3"
            ;;
    esac
    printf '\n'
}

render() {
    cat <<'EOF'
# Runtime dependencies

Whisky's app code is built from this repo, but the Wine runtime it downloads on first launch
(`Libraries.tar.gz`) is assembled from upstream binaries. This page explains what each component
does and how they fit together; the pinned versions are in [Pinned versions](#pinned-versions).

It is generated from [`scripts/config/sources.yml`](https://github.com/CHE3MZ/whisky/blob/master/scripts/config/sources.yml) by
[`scripts/upstream/report.sh`](https://github.com/CHE3MZ/whisky/blob/master/scripts/upstream/report.sh). Change the pins there and re-run
the script rather than editing this file.

See the [release workflow](../project/release-workflow.md) for how the runtime and app are assembled and
published.

## Components

EOF

    while IFS="$SEP" read -r id name link commit release; do
        [ -n "$id$name" ] || continue
        documents_source "$id" || continue
        component_description "$id" "$name" "$link"
    done < "$1"

    cat <<'EOF'
### D3DMetal (Apple Game Porting Toolkit)

Apple's proprietary Direct3D → Metal translation layer, distributed only inside the Game Porting
Toolkit. Whisky uses it as a backend when a GPTK payload is present on disk. It is not
redistributable: Apple's GPTK license governs it, so it is never bundled in the published runtime.

### MoltenVK — Vulkan → Metal

Translates Vulkan into Metal, the piece that makes the DXVK path possible on macOS. It ships inside
the Gcenx Wine build rather than as an independently pinned download, so the chain is
DXVK → MoltenVK → Metal.

### msync — fast synchronization primitives

A Mach-based synchronization patch in the Gcenx Wine build that speeds up multi-threaded Windows
programs, games especially, by avoiding slower emulated synchronization. It patches Wine itself, so
it benefits every backend and is not separately selectable.

### winetricks (and its verb catalog `verbs.txt`)

A script that downloads and installs common Windows components (VC++ runtimes, .NET, DirectX, fonts)
into a bottle's prefix. `verbs.txt` is the catalog of verbs the in-app browser lists, generated with
`winetricks list-all`. It runs inside a Wine prefix after the bottle exists, provisioning what a
game needs on top of the runtime.

### cabextract

Extracts the Microsoft `.cab` archives that many winetricks verbs download. winetricks calls it
during component installs, and it rides app releases rather than runtime ones.

## How they connect

The components form one stack, chosen per bottle:

```
Windows game (.exe)
  └── Wine ────┬── DXVK ──────────────► MoltenVK ──► Metal
               ├── DXMT ───────────────────────────► Metal
               └── D3DMetal (if GPTK present) ─────► Metal
```

Wine is the base in every bottle, and msync patches its synchronization. Graphics is where the
pieces stack: a Direct3D call goes through DXVK and then MoltenVK to reach Metal, or straight to
Metal through DXMT, with D3DMetal as a third option when a GPTK payload is present. Whisky picks one
backend per bottle.

Provisioning happens separately: winetricks and cabextract install Windows components into a bottle
after it is created. The runtime archive bundles Wine, MoltenVK, msync and the DXVK/DXMT payloads;
the app bundle carries winetricks, `verbs.txt` and cabextract; D3DMetal is used only when the user
already has a GPTK copy.

## Pinned versions

Read from `sources.yml` by `report.sh`. Do not hand-edit.

| Component | Pinned version | Upstream source |
|-----------|----------------|-----------------|
EOF

    while IFS="$SEP" read -r id name link commit release; do
        [ -n "$id$name" ] || continue
        documents_source "$id" || continue
        if [ -n "$release" ]; then
            pin=$release
        elif [ -n "$commit" ]; then
            pin=$(printf '%s' "$commit" | cut -c1-12)
        else
            pin='—'
        fi
        slug=$(printf '%s' "$link" | sed -e 's#^https\?://github.com/##' -e 's#/*$##')
        [ -n "$slug" ] || slug=$link
        printf "| %s | \`%s\` | [%s](%s) |\n" "$name" "$pin" "$slug" "$link"
    done < "$1"

    cat <<'EOF'

MoltenVK and msync have no separate pin; their versions are whatever the pinned Gcenx Wine build
ships. D3DMetal has no GitHub release feed and is tracked manually. winetricks and cabextract ride
app releases.

## Runtime archive integrity (manual)

The app verifies each downloaded `Libraries.tar.gz` against the SHA-256 recorded in
[`WhiskyWineVersion.plist`](https://che3mz.github.io/whisky/WhiskyWineVersion.plist) and fails closed on a
mismatch. These digests are not derived from `sources.yml`, so add a row whenever a runtime release
is published.

| Runtime | SHA-256 |
|---------|---------|
| `v3.1.1` | `01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3` |
| `v3.1.0` | `86e2d54a60736f27e6ce82cacf2a91e500c20f6d32ae959a16afd912e6b03096` |
| `v3.0.0` | `9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025f8` |

## Keeping this current

[`TrackUpstream.yml`](https://github.com/CHE3MZ/whisky/blob/master/.github/workflows/TrackUpstream.yml) runs
[`track.sh`](https://github.com/CHE3MZ/whisky/blob/master/scripts/upstream/track.sh) weekly against the pins in `sources.yml` and opens an
issue in `CHE3MZ/whisky` when a tracked source moves. After changing a pin, run
`./scripts/upstream/report.sh` to regenerate this file; CI runs `report.sh --check` and fails if it
is stale.
EOF
}

out=$(mktemp "${TMPDIR:-/tmp}/whisky-deps.XXXXXX")
parsed=$(mktemp "${TMPDIR:-/tmp}/whisky-deps.XXXXXX")
existing=$(mktemp "${TMPDIR:-/tmp}/whisky-deps.XXXXXX")
trap 'rm -f "$out" "$parsed" "$existing"' 0 1 2 3 15

parse_sources "$SOURCES_FILE" > "$parsed"

entry_count=$(awk -F"$SEP" 'NF { n++ } END { print n + 0 }' "$parsed")
if [ "$entry_count" -eq 0 ]; then
    printf 'error: no sources found in %s\n' "$SOURCES_FILE" >&2
    exit 1
fi

render "$parsed" > "$out"

if [ "$CHECK" -eq 1 ]; then
    if [ -f "$OUTPUT_FILE" ]; then
        # Ignore CRLF so a Windows checkout (core.autocrlf) is not a false stale.
        tr -d '\r' < "$OUTPUT_FILE" > "$existing"
        if cmp -s "$out" "$existing"; then
            printf '%s is up to date.\n' "$OUTPUT_FILE"
            exit 0
        fi
    fi
    printf '%s is out of date; run scripts/upstream/report.sh\n' "$OUTPUT_FILE" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
cp "$out" "$OUTPUT_FILE"
printf 'Wrote %s\n' "$OUTPUT_FILE"
