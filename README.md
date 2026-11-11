<div align="center">

  # Whisky 🥃
  *Wine but a bit stronger*

  > **Active community fork.** The original [whisky-app/whisky](https://github.com/whisky-app/whisky)
  > was archived on April 9, 2025 with a final maintenance notice. This fork, maintained by
  > [@CHE3MZ](https://github.com/CHE3MZ), continues development — addressing the backlog of
  > upstream issues and adding new functionality. Not affiliated with the original project or
  > getwhisky.app.

  ![](https://img.shields.io/github/actions/workflow/status/CHE3MZ/whisky/CI.yml?style=for-the-badge&label=CI)
  [![](https://img.shields.io/codecov/c/github/CHE3MZ/whisky?style=for-the-badge&logo=codecov&label=Coverage&flag=whiskykit)](https://codecov.io/gh/CHE3MZ/whisky)
  [![](https://img.shields.io/github/downloads/CHE3MZ/whisky/total?style=for-the-badge&logo=github&label=Downloads)](https://github.com/CHE3MZ/whisky/releases)
  [![](https://img.shields.io/github/downloads/CHE3MZ/whisky/latest/total?style=for-the-badge&label=Latest)](https://github.com/CHE3MZ/whisky/releases/latest)
  [![](https://img.shields.io/github/issues/CHE3MZ/whisky?style=for-the-badge)](https://github.com/CHE3MZ/whisky/issues)
  [![Documentation](https://img.shields.io/badge/Documentation-DocC-blue?style=for-the-badge)](https://che3mz.github.io/whisky/documentation/whiskykit/)
</div>

## Overview

Whisky provides a clean and easy-to-use graphical wrapper for Wine built in native SwiftUI. You can make and manage bottles, install and run Windows apps and games, and unlock the full potential of your Mac with no technical knowledge required.

<img width="650" alt="Whisky in action" src="./docs/assets/demo.gif">

<img width="650" alt="Config" src="./docs/assets/config-screenshot.png">

*Familiar UI that integrates seamlessly with macOS*

<div align="right">
  <img width="650" alt="New Bottle" src="./docs/assets/new-bottle-screenshot.png">

  *One-click bottle creation and management*
</div>

<img width="650" alt="debug" src="./docs/assets/debug-screenshot.png">

*Debug and profile with ease*

---

## Key Features

- **Wine 11.0** - Latest stable Wine with improved compatibility and networking
- **DXMT & DXVK Graphics** - DirectX 11 through native Metal translation (DXMT) out of the box, with DXVK over MoltenVK as the universal fallback
- **Launcher Compatibility** - Built-in support for Steam, Epic, EA App, Rockstar, Battle.net, and more
- **Controller Support** - SDL environment variable controls for gamepad detection and mapping issues
- **Stability Diagnostics** - One-click diagnostic reports for troubleshooting crashes and freezes
- **Native SwiftUI** - Beautiful, familiar macOS interface

## System Requirements

- **CPU**: Apple Silicon (M-series chips)
- **OS**: macOS Sequoia 15.0 or later

## Installation

### Homebrew (recommended)

```sh
brew install --cask CHE3MZ/tools/whisky
```

This taps [CHE3MZ/homebrew-tools](https://github.com/CHE3MZ/homebrew-tools) and installs the latest signed/notarized DMG. `brew upgrade --cask` picks up new releases.

> The default `brew install --cask whisky` still installs the **archived original** (last release April 2025) and always will until that cask is updated. Use the qualified `CHE3MZ/tools/whisky` form to get this fork.

### Manual

1. Download the latest **[Whisky-X.Y.Z.dmg](https://github.com/CHE3MZ/whisky/releases/latest)** (signed and notarized — Gatekeeper-approved).
2. Open the DMG and drag **Whisky.app** to **/Applications**.
3. Launch Whisky. On first run it downloads the Wine runtime (~330 MB) and sets up your default bottle.

In-app updates are delivered through Sparkle from `https://che3mz.github.io/whisky/appcast.xml`.

### Migrating from the original Whisky

The original [whisky-app/whisky](https://github.com/whisky-app/whisky) was archived on **April 9, 2025** with a final maintenance notice. If you're running it today, you're on a stale build with no path forward for new fixes. This fork picks up where the upstream left off — version `3.0.1` shipped 54 requirements covering the 10 categories of upstream issue tracking (#40–#50).

To switch:

1. Install this fork: `brew install --cask CHE3MZ/tools/whisky` or follow the manual steps above.
2. Open it and choose **File → Migrate from the Original Whisky**. It finds the bottles the original app left in `~/Library/Containers/com.isaacmarovitz.Whisky/` and imports the ones you pick. Bottles are referenced **in place** — nothing is moved or copied — so the original app keeps working if you'd like to keep it around.
3. *(Optional)* Once you're happy, remove the original app: drag **/Applications/Whisky.app** to the Trash, or `brew uninstall --cask whisky` if you installed it via Homebrew. Your bottles stay put.

The original app uses a different bundle identifier (`com.che3mz.whisky` here vs. `com.isaacmarovitz.Whisky`), which is why bottles aren't shared automatically. The old **Bottle → Export** / **File → Import Bottle** route still works if you'd rather move bottles by hand or onto another Mac. With no critical bottles, you can skip migration entirely — the new app creates a fresh bottle on first launch.

> **Upgrading from an earlier `com.franke.Whisky` build?** This fork now keeps its files under `Whisky` folders (for example `~/Library/Application Support/Whisky`) instead of the bundle identifier. Move your data once:
>
> ```sh
> mkdir -p "$HOME/Library/Application Support/Whisky"
> for old in com.franke.Whisky com.che3mz.whisky; do
>   mv "$HOME/Library/Application Support/$old/"* "$HOME/Library/Application Support/Whisky/" 2>/dev/null || true
>   mv "$HOME/Library/Containers/$old/BottleVM.plist" "$HOME/Library/Application Support/Whisky/" 2>/dev/null || true
>   mv "$HOME/Library/Containers/$old/GameRouting.plist" "$HOME/Library/Application Support/Whisky/" 2>/dev/null || true
>   mv "$HOME/Library/Containers/$old/Bottles" "$HOME/Library/Application Support/Whisky/" 2>/dev/null || true
> done
> defaults export com.franke.Whisky /tmp/whisky-old.plist 2>/dev/null || true
> defaults import com.che3mz.whisky /tmp/whisky-old.plist 2>/dev/null || true
> rm -f /tmp/whisky-old.plist
> ```
>
> Caches, logs, and HTTP storage can be discarded; the app recreates them.

## Uninstalling

Dragging **Whisky.app** to the Trash (or `brew uninstall --cask CHE3MZ/tools/whisky`) removes the app but leaves the Wine runtime, your bottles, and app data behind — by design, so reinstalling doesn't re-download ~330 MB or lose your bottles.

> ⚠️ **Back up your bottles first if you want to keep them.** Removing the `Whisky` folder below deletes every bottle stored in its default location. Bottles you created in a custom folder live wherever you put them — check **Bottle → Reveal in Finder** before deleting anything.

To remove Whisky **completely**, delete the app and then these paths (all under `~/Library`):

```sh
# 1. The app itself
rm -rf "/Applications/Whisky.app"          # or: brew uninstall --cask CHE3MZ/tools/whisky

# 2. Bottles, bottle registry, and the ~330 MB Wine runtime (default location)
rm -rf ~/Library/Application\ Support/Whisky

# 3. Caches and logs
rm -rf ~/Library/Caches/Whisky
rm -rf ~/Library/Logs/Whisky

# 4. System-managed files that stay named after the bundle identifier
rm -rf ~/Library/HTTPStorages/com.che3mz.whisky
rm -f  ~/Library/Preferences/com.che3mz.whisky.plist
rm -rf ~/Library/Saved\ Application\ State/com.che3mz.whisky.savedState
rm -rf ~/Library/Containers/com.che3mz.whisky.WhiskyThumbnail
```

If you also installed bottles in a **custom location**, delete those folders too. Migrated bottles that still belong to the original app live under `~/Library/Containers/com.isaacmarovitz.Whisky` and are left untouched by the steps above.

## Documentation

- **[Support](docs/support.md)** - Where to file bugs and what to expect from a single-maintainer fork
- **[Governance & continuity](docs/GOVERNANCE.md)** - Who maintains this and the honest bus-factor situation
- **[Runtime dependencies](docs/misc/dependencies.md)** - The bundled Wine/DXVK/D3DMetal/DXMT versions and their upstream sources

WhiskyKit, the core framework powering Whisky, has comprehensive API documentation:

- **[WhiskyKit API Documentation](https://che3mz.github.io/whisky/documentation/whiskykit/)** - Full API reference with usage examples
- **[Getting Started Guide](https://che3mz.github.io/whisky/documentation/whiskykit/gettingstarted)** - Learn how to integrate WhiskyKit
- **[Architecture Overview](https://che3mz.github.io/whisky/documentation/whiskykit/architecture)** - Understand how WhiskyKit components work together

### Troubleshooting

- **[Launcher Troubleshooting](docs/support/LauncherTroubleshooting.md)** - Fix issues with Steam, Epic, Battle.net, etc.
- **[Steam Compatibility Guide](docs/support/SteamCompatibility.md)** - Detailed guide for Steam on Whisky
- **[Stability Troubleshooting](docs/support/StabilityTroubleshooting.md)** - Diagnose crashes, freezes, reboots, and kernel panics
- **Controller Issues** - Enable "Controller Compatibility Mode" in Bottle Config → Controller & Input
- **[Game Configurations](https://github.com/CHE3MZ/whisky/blob/master/WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json)** - 80+ curated per-game compatibility configs, also browsable in-app under Game Configurations

### Upstream issue audit

Per-issue accounting of how this fork addresses the open issues from the
archived upstream repo. Read [docs/AUDIT.md](docs/AUDIT.md) for the
methodology — including how to read the `addressed-direct` vs
`addressed-categorical` distinction and what `unverified` GameDB entries
actually mean.

### Test coverage

The Coverage badge above is scoped to the **`whiskykit` flag** — line
coverage of the framework that holds the bottle, Wine, GameDB, and
PE-parser logic, measured by `swift test --enable-code-coverage` per
[`.github/workflows/CI.yml`](.github/workflows/CI.yml). The blended
project-wide number on the [Codecov dashboard](https://codecov.io/gh/CHE3MZ/whisky)
reads much lower because it averages in the SwiftUI app target, which
only receives best-effort UI-test coverage. Read the badge as
"WhiskyKit unit-test coverage," not full-app coverage.

WhiskyUITests gives behavioural coverage of the SwiftUI surface (toolbar,
create-bottle sheet, fixture-dependent flows). CI now runs them with
`-enableCodeCoverage YES` and uploads the resulting app-target coverage to
Codecov under a separate `whiskyapp` flag (best-effort — the upload never gates
CI). Because UI tests exercise far less of the app than the unit tests do of
WhiskyKit, expect the app-target number to read lower than the WhiskyKit badge
above.

---

## Credits & Acknowledgments

Whisky is possible thanks to the magic of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [DXMT](https://github.com/3Shain/dxmt) by 3Shain
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, Nat Brown, and [Isaac Marovitz](https://github.com/IsaacMarovitz) (original author) for their support and contributions!
