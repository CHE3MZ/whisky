# Release Workflow

This document describes how to cut a release of the Whisky app and how to publish a new Wine Libraries archive.

The fork uses two parallel artifact streams:

- **App releases** (`app-vX.Y.Z`) — `Whisky-X.Y.Z.dmg`, signed and notarized for direct distribution.
- **Wine Libraries releases** (`vX.Y.Z`) — `Libraries.tar.gz` containing the Wine/DXVK runtime that the app downloads on first launch.

Both live on GitHub Releases. The Wine version plist is served from GitHub Pages, which is **workflow-deployed** through `.github/workflows/Documentation.yml` (the `gh-pages` branch is unused; static files go in `dist/pages/`). The Sparkle feed is generated per release, attached to that release as `appcast.xml`, and mirrored to the historical Pages URL at deploy time, so no appcast file is committed or edited by hand.

## One-time setup

These only need to be done once per maintainer machine.

### Apple Developer ID Application certificate

A Developer ID Application certificate is required to ship a Gatekeeper-friendly DMG. Apple Development and Apple Distribution certs are not sufficient.

1. **Xcode → Settings → Accounts** → select your Apple ID → **Manage Certificates…**
2. Click **+** → **Developer ID Application**
3. The cert is installed in your login keychain automatically.

### notarytool credentials

Apple's notary service needs an app-specific password.

1. Generate one at <https://appleid.apple.com> → **Sign-In and Security → App-Specific Passwords**.
2. Store it as a notarytool keychain profile:
   ```sh
   xcrun notarytool store-credentials AC_PASSWORD \
     --apple-id <your-apple-id-email> \
     --team-id UYNK59NFK8 \
     --password <app-specific-password>
   ```
3. The release script reads this profile by name (`AC_PASSWORD`). The signing team is `UYNK59NFK8`, set in the Xcode project and `scripts/config/exportOptions.plist`.

### create-dmg

The release script builds a styled DMG with [create-dmg](https://github.com/sindresorhus/create-dmg) (background, Applications shortcut, and icon layout). Install Node.js 20 or later, then:

```sh
npm install --global create-dmg
```

### Release workflow secrets

Pushing an `app-vX.Y.Z` tag runs `.github/workflows/Release.yml` on a `macos-26` runner. Add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | base64 of a Developer ID Application `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `KEYCHAIN_PASSWORD` | any random password for the temporary CI keychain |
| `APPLE_ID` | Apple ID for notarytool |
| `APPLE_APP_SPECIFIC_PASSWORD` | app-specific password for notarytool |
| `APPLE_TEAM_ID` | optional; defaults to `UYNK59NFK8` |
| `SPARKLE_ED_PRIVATE_KEY` | base64 of the exported Sparkle Ed25519 private key (signs the appcast in CI) |
| `BREW_TOKEN` | personal access token for the Homebrew tap workflow |

CI archives with manual Developer ID signing (`ARCHIVE_CODE_SIGN_STYLE=Manual`, `ARCHIVE_CODE_SIGN_IDENTITY=Developer ID Application`), so only the Developer ID certificate is needed there. The local fallback below still archives with Apple Development signing and re-signs on export.

Encode a `.p12` for the secret with:

```sh
base64 -i certificate.p12 | pbcopy
```

### Sparkle EdDSA keys

A keypair is needed to sign appcast entries. Sparkle's `generate_keys` tool ships with the Sparkle SPM package; after building Whisky once, find it at:

```
~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

Run it once. The private key is stored automatically in your login keychain. The public key is printed to stdout — it is committed in `Whisky/Info.plist` under `SUPublicEDKey`. If you regenerate keys you will invalidate the existing public key in the bundled app and need to re-release.

> **Fork note.** This fork does not have the upstream Whisky signing key and cannot continue its update chain. It uses its own keypair, so installs of the upstream app must update to a build from this fork **once, manually** (or via Homebrew); after that, Sparkle auto-updates work normally with the fork's key. Treat the first fork release as a migration release and say so in the release notes.

The release workflow also needs the same key as the repository secret `SPARKLE_ED_PRIVATE_KEY`. Export it and copy the base64 to **Settings → Secrets and variables → Actions**:

```sh
SPARKLE_BIN=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
"$SPARKLE_BIN/generate_keys" -x sparkle_ed25519_private.key
base64 -i sparkle_ed25519_private.key | pbcopy
rm sparkle_ed25519_private.key
```

CI decodes the secret and passes it to `sign_update --ed-key-file`, so the key never appears in the workflow logs.

## Credential continuity (backup & recovery)

Three secrets gate the release pipeline. Losing the Sparkle key is **unrecoverable** for existing installs: `SUPublicEDKey` is baked into every shipped `Info.plist`, so a regenerated key permanently strands all installed copies off auto-update. Keep current, restore-tested backups of all three. (A fourth credential, the `BREW_TOKEN` repository secret used by the release step that publishes to [CHE3MZ/homebrew-tools](https://github.com/CHE3MZ/homebrew-tools), is regenerable and so needs no backup — the three-secrets focus here is on the non-regenerable ones.)

| Secret | Where it lives | If lost |
| --- | --- | --- |
| Sparkle EdDSA private key | login keychain ("Private key for signing Sparkle updates") and the `SPARKLE_ED_PRIVATE_KEY` repository secret | Existing installs never see another auto-update |
| Developer ID Application identity | login keychain | Re-issue from the Apple Developer portal; releases blocked until done |
| notarytool app-specific password | appleid.apple.com; cached as keychain profile `AC_PASSWORD` | Regenerate at appleid.apple.com, re-run `store-credentials` |

### Backup procedure

1. Export the Sparkle private key (Keychain will prompt for access):

   ```sh
   SPARKLE_BIN=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
   "$SPARKLE_BIN/generate_keys" -x sparkle_ed25519_private.key
   ```

   If several `Whisky-*` DerivedData directories exist this picks the most recently modified one.

2. Export the Developer ID identity: **Keychain Access → My Certificates** → right-click *Developer ID Application: …* → **Export** as `.p12` with a strong password.
3. Encrypt both files before they leave the machine:

   ```sh
   age -p sparkle_ed25519_private.key > sparkle_ed25519_private.key.age   # or: gpg -c <file>
   age -p developer_id.p12 > developer_id.p12.age
   ```

   Neither `age` nor `gpg` ships with macOS; install `age` with `brew install age`.

4. Store the encrypted files — plus the app-specific password itself — in **two** off-machine locations (e.g. a password-manager secure note and one offline medium). Delete the plaintext exports afterwards.
5. Record the certificate expiry date and set reminders at T-60 and T-14 days:

   ```sh
   security find-certificate -c "Developer ID Application" -p | openssl x509 -noout -enddate
   ```

   This prints the first matching certificate only. During a renewal window, when the
   old and new certificates coexist in the keychain, check every match with
   `security find-certificate -a -c "Developer ID Application" -p` (each `-----BEGIN`
   block is one certificate) — and re-run this step after the renewal so the reminder
   tracks the new expiry, not the old one.

### Restore test (do this the day the backup is made)

A backup that has never been restored from is a hope, not a backup. `sign_update` can sign directly from a key file, so the test never touches the keychain:

```sh
"$SPARKLE_BIN/sign_update" --ed-key-file sparkle_ed25519_private.key build/release/Whisky-X.Y.Z.dmg
```

The printed `sparkle:edSignature` **and** the printed `length` must both exactly match the `appcast.xml` asset attached to that release (download it with `gh release download app-vX.Y.Z --pattern appcast.xml`). Ed25519 signatures are deterministic, so a mismatch in either means a wrong key or a non-canonical DMG: the exported key is wrong **or** the DMG you signed is not the exact published artifact (rebuilt locally, partially downloaded, wrong file). If in doubt, download the release asset from the appcast enclosure URL and sign that.

### Recovery on a new machine

0. Build Whisky once first so the Sparkle tools exist in DerivedData (see [Sparkle EdDSA keys](#sparkle-eddsa-keys) under One-time setup) — `generate_keys` ships inside the Sparkle SPM artifact, not on `PATH`. Re-declare `SPARKLE_BIN` in this fresh shell (it is only set earlier in the Backup section):

   ```sh
   SPARKLE_BIN=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
   ```

   If several `Whisky-*` DerivedData directories exist this picks the most recently modified one.
1. Decrypt the backup (`age -d sparkle_ed25519_private.key.age > sparkle_ed25519_private.key`, entering the backup passphrase), then import the Sparkle key: `"$SPARKLE_BIN/generate_keys" -f sparkle_ed25519_private.key`. If an existing item named *Private key for signing Sparkle updates* is already in the login keychain, the import may fail until that item is removed via Keychain Access. Delete the decrypted plaintext key once the import succeeds.
2. Open the `.p12` to install the Developer ID identity into the login keychain.
3. Re-create the notary profile with `xcrun notarytool store-credentials AC_PASSWORD …` (see One-time setup).

## Automated release

1. Run `task changelog` and commit `docs/CHANGELOG.md`.
2. Commit and push to `master`.
3. Push an `app-vX.Y.Z` tag:
   ```sh
   git tag -a app-vX.Y.Z -m "Whisky X.Y.Z"
   git push origin app-vX.Y.Z
   ```
4. The `Release` workflow runs on `macos-26`, builds/signs/notarizes/staples the DMG with `create-dmg`, signs it for Sparkle, generates `appcast.xml`, and publishes the release with both assets. The release is created as a draft and published only after both assets are attached, so the Pages mirror never reads a partial release.
5. The workflow then dispatches `Documentation.yml`, which mirrors the newest app release's `appcast.xml` to the historical Pages URL. No appcast file is committed or edited by hand.
6. The Homebrew tap updates automatically when the release is published.

The release script injects `MARKETING_VERSION` from the requested version (the tag in CI) and a UTC-timestamp `CURRENT_PROJECT_VERSION` at archive time, so there is no version bump to commit. The checked-in project keeps the neutral development values (`MARKETING_VERSION = 0.0.0`). The injected build number is printed in the workflow run summary and written to `build/release/build-number.txt`; the release workflow passes it to `scripts/appcast.sh` for `sparkle:version`.

> Releases published before this automation (for example `app-v3.7.0`) have no `appcast.xml` asset. Until the first release made by the updated workflow exists, `Documentation.yml` logs a warning and reuses the currently deployed feed, so Pages keeps serving updates without a gap.

## Manual app release (fallback)

> This local flow is a fallback. Do not push the tag yourself: `gh release create` creates it, so the automated `Release` workflow does not run on top of the manual release. Use one path or the other.

### 1. No version bump needed

`scripts/release.sh X.Y.Z` injects the version from its argument (`MARKETING_VERSION`) and a UTC-timestamp build number (`CURRENT_PROJECT_VERSION`) at archive time. The checked-in project keeps the neutral development value `MARKETING_VERSION = 0.0.0`, so there is nothing to edit or commit for a release.

### 2. Update the changelog

Run `task changelog` (see `Taskfile.yml`) to regenerate `docs/CHANGELOG.md`, then commit and push it to `master` before publishing the release.

### 3. Build, sign, notarize, package

```sh
scripts/release.sh X.Y.Z
```

The script:

1. Archives the app with `MARKETING_VERSION` from the argument and a UTC-timestamp `CURRENT_PROJECT_VERSION` (Apple Development by default; CI overrides to manual Developer ID signing), then verifies the exported app's `Info.plist` reports the requested version and build.
2. Re-signs on export with **Developer ID Application** per `scripts/config/exportOptions.plist`.
3. Verifies the signature with `codesign --verify --deep --strict`.
4. Builds a styled DMG with `create-dmg` (background, Applications shortcut, and icon layout).
5. Signs the DMG with the Developer ID Application certificate.
6. Submits the DMG to Apple's notary service and waits for the verdict (typically 5–15 minutes).
7. Staples the notarization ticket.
8. Verifies the stapled DMG passes `spctl --assess`.

The artifact lands at `build/release/Whisky-X.Y.Z.dmg`.

### 4. Generate the appcast

`scripts/appcast.sh` signs the DMG with the Sparkle key from your login keychain and writes a single-item feed:

```sh
bash scripts/appcast.sh \
  --version X.Y.Z \
  --build "$(cat build/release/build-number.txt)" \
  --dmg build/release/Whisky-X.Y.Z.dmg \
  --repo CHE3MZ/whisky \
  --output build/release/appcast.xml
```

### 5. Publish the release with both assets

Create the release as a draft, attach the DMG and the feed, then publish it:

```sh
gh release create app-vX.Y.Z --repo CHE3MZ/whisky \
  --draft --title "Whisky X.Y.Z" --notes "..."
gh release upload app-vX.Y.Z --repo CHE3MZ/whisky \
  build/release/Whisky-X.Y.Z.dmg build/release/appcast.xml
gh release edit app-vX.Y.Z --repo CHE3MZ/whisky --draft=false
```

### 6. Refresh the Pages mirror

```sh
gh workflow run Documentation.yml --repo CHE3MZ/whisky
```

The workflow mirrors the newest app release's `appcast.xml` to `https://che3mz.github.io/whisky/appcast.xml` within ~1–2 minutes. Sparkle clients pick up the update on their next check.

### 7. Homebrew tap (automatic)

Publishing the `app-vX.Y.Z` release fires `.github/workflows/UpdateHomebrewTap.yml`,
which downloads the DMG, computes its sha256, and bumps the
[CHE3MZ/homebrew-tools](https://github.com/CHE3MZ/homebrew-tools) cask so
`brew install --cask CHE3MZ/tools/whisky` tracks the new version. No manual edit needed.

This requires a one-time repository secret **`BREW_TOKEN`** — a personal access token
(classic `repo`, or fine-grained with **Contents: write**) for `CHE3MZ/homebrew-tools`;
the default `GITHUB_TOKEN` cannot push to another repository. If the secret is missing the
workflow fails loudly so the drift is visible. You can also re-sync any tag manually via the
workflow's `workflow_dispatch` input.

## Wine Libraries release

The runtime (`Libraries.tar.gz`) is **assembled from upstream binaries, not built from source** — see
[`dependencies.md`](misc/dependencies.md) for the authoritative list of components,
their pinned versions, and where each comes from. When the runtime needs to change:

1. **Assemble `Libraries.tar.gz`** from the pinned upstream binaries. The archive unpacks to a
   `Libraries/` tree the app expects (`Libraries/Wine/bin/…` is the Wine binary dir per
   `WhiskyWineInstaller.binFolder`). To reproduce a build:
   - Download the pinned **Wine** build (Gcenx `macOS_Wine_builds`) and unpack it as `Libraries/Wine/`.
   - Add the pinned **DXVK-macOS** DLLs and **DXMT** prebuilt release into the runtime per the Gcenx
     layout.
   - Place **D3DMetal** as extracted from Apple's Game Porting Toolkit. ⚠️ Redistribution is governed by
     Apple's GPTK license — confirm terms before publishing.
   - Bump the matching `commit`/`release` values in `scripts/config/sources.yml` and run
     `scripts/upstream/report.sh` to refresh `docs/misc/dependencies.md`, so drift detection stays
     accurate.
   - `tar -czf Libraries.tar.gz Libraries/` (mind the `Tar` pipe-drain pitfall noted below).
2. Tag with the bare version `vX.Y.Z` (no `app-` prefix).
3. `gh release create vX.Y.Z --title "Wine Libraries vX.Y.Z" Libraries.tar.gz`.
4. Compute the SHA-256 of the **exact published asset** — the app verifies the download against this
   and fails closed on a mismatch, so an incorrect value blocks every fresh install:
   ```sh
   shasum -a 256 Libraries.tar.gz
   ```
5. Update `dist/pages/WhiskyWineVersion.plist` with the version, bundled DXVK version, and the digest
   from the previous step. Record the same digest in the runtime-integrity table in
   [`dependencies.md`](misc/dependencies.md):
   ```xml
   <dict>
       <key>version</key>
       <dict>
           <key>major</key><integer>X</integer>
           <key>minor</key><integer>Y</integer>
           <key>patch</key><integer>Z</integer>
       </dict>
       <key>dxvkVersion</key>
       <string>1.10.3</string>
       <key>sha256</key>
       <string>…64-hex-digest…</string>
   </dict>
   ```
6. Commit and push. The Documentation workflow republishes Pages, and existing app installs prompt to update on their next Wine version check.

## URLs the app depends on

- `https://che3mz.github.io/whisky/WhiskyWineVersion.plist` — Wine version metadata
- `https://che3mz.github.io/whisky/appcast.xml` — Sparkle update feed (mirrored at deploy time from the newest app release's `appcast.xml` asset)
- `https://github.com/CHE3MZ/whisky/releases/download/app-vX.Y.Z/appcast.xml` — per-release signed feed/signature asset
- `https://github.com/CHE3MZ/whisky/releases/download/vX.Y.Z/Libraries.tar.gz` — Wine binary archive
- `https://github.com/CHE3MZ/whisky/releases/download/app-vX.Y.Z/Whisky-X.Y.Z.dmg` — app DMG

## Pitfalls

- **Don't override `CODE_SIGN_IDENTITY` at archive time.** The project is configured for Apple Development with automatic signing; overriding it conflicts with provisioning. The release script lets `xcodebuild archive` use the project default and re-signs on export.
- **Don't bundle the WhiskyKit folder as Resources.** Doing so packages the package's `.build` directory (DocC plugin executables) into the app, and Apple's notary rejects the archive because those plugin executables don't have hardened runtime. The PBXResourcesBuildPhase entry for `WhiskyKit` was removed from the project for this reason; do not add it back. The PBXFileReference and PBXGroup entries must remain or Xcode's SPM workspace integration crashes on CI.
- **Pipe deadlocks in `Tar`.** `process.waitUntilExit()` must come *after* draining the pipe, not before. The verbose tar listing for a multi-hundred-megabyte archive will overflow the OS pipe buffer. See the fix in 3.0.1.
