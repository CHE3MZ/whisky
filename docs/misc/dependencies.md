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

### Whisky upstream — the project this fork tracks

The upstream Whisky project. Its commit is pinned so app-level changes (bug fixes, UI, bottle
handling) are reviewed and merged deliberately instead of drifting in. It is the codebase this fork
is built from, tracked alongside the runtime binaries so movement in either shows up in one place.

### Wine — the Windows runtime

Wine implements the Windows API so Windows `.exe`/`.dll` binaries run natively on macOS without a
virtual machine. Whisky ships Gcenx's macOS build of Wine as `Libraries/Wine/`, and every bottle
runs inside it. DXVK and DXMT replace its Direct3D translation, MoltenVK and msync extend its
graphics and synchronization layers, and winetricks installs Windows components into a bottle's
Wine prefix.

### DXVK (macOS) — Direct3D 9/10/11 → Vulkan

DXVK translates Direct3D 9/10/11 calls into Vulkan; on macOS that Vulkan comes from MoltenVK, so the
chain runs Direct3D → DXVK → MoltenVK → Metal. It is the default rendering backend for most games
and is selected per bottle.

The 1.10.x line is frozen on purpose: the 2.x series needs Vulkan 1.3 extensions MoltenVK/macOS do
not expose, so an upstream 2.x release is not a reason to bump it.

### DXMT — Direct3D 11 → Metal

DXMT translates Direct3D 11 straight to Metal and is selectable per bottle as an alternative to DXVK
for D3D11 titles. Whisky strips Wine's "builtin DLL" marker from the DXMT trio so it loads as native,
and pairs it with Wine's `winemetal` shim.

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
| Whisky Upstream | `3abfbae945e3` | [frankea/Whisky](https://github.com/frankea/Whisky) |
| Wine MacOS Builds | `11.0_1` | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) |
| DXVK MacOS | `v1.10.3-20230507-repack` | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) |
| DXMT MacOS | `v0.80` | [3Shain/dxmt](https://github.com/3Shain/dxmt) |

MoltenVK and msync have no separate pin; their versions are whatever the pinned Gcenx Wine build
ships. D3DMetal has no GitHub release feed and is tracked manually. winetricks and cabextract ride
app releases.

## Runtime archive integrity (manual)

The app verifies each downloaded `Libraries.tar.gz` against the SHA-256 recorded in
[`docs/WhiskyWineVersion.plist`](https://github.com/CHE3MZ/whisky/blob/master/docs/WhiskyWineVersion.plist) and fails closed on a
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
