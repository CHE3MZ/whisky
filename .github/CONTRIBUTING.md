# How to Contribute

Thanks for your interest! First, make a fork of Whisky, create a new branch for your changes, and get coding!

## Build Environment

Whisky is built using **Xcode 16** on **macOS Sequoia 15.0** or later. All external dependencies are handled through the Swift Package Manager.

## Code Style

### Linting with SwiftLint

Every Whisky commit is automatically linted using SwiftLint. You can run these checks locally by building in Xcode; violations will appear as errors or warnings. For your pull request to be merged, you must meet all requirements outlined by SwiftLint and have no violations.

### Formatting with SwiftFormat

We use [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to maintain consistent code formatting. This is enforced in CI alongside SwiftLint.

**Required Version: 0.58.7**

Using a different version may produce different formatting results. CI uses this exact version.

#### Installation

**Option 1: Homebrew (latest version)**
```bash
brew install swiftformat
swiftformat --version  # Verify version matches 0.58.7
```

**Option 2: Download specific version (recommended)**
```bash
curl -LO https://github.com/nicklockwood/SwiftFormat/releases/download/0.58.7/swiftformat.zip
unzip swiftformat.zip
sudo mv swiftformat /usr/local/bin/
```

**Option 3: Nix**

If you use Nix, the repository flake provides a dev shell with SwiftFormat
pinned to exactly the version above (plus SwiftLint):
```bash
nix develop
swiftformat --version  # 0.58.7
```

#### Usage

To format all Swift files in the project:
```bash
swiftformat .
```

To check formatting without making changes:
```bash
swiftformat --lint .
```

#### Pre-commit Hook (Recommended)

To automatically check formatting before each commit:
```bash
cp .github/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Localization

All user-facing strings must be localized. Add every new string to the
English (source) entries in `Whisky/Localizable.xcstrings`. **Do not add
other-language translations, and do not edit another language's entries, in a
PR** — hand-editing the string catalog tends to re-serialize the whole file
(producing huge, unreviewable diffs) and can silently drop existing
translations.

Translations are managed through Crowdin and synced automatically: the
[`Crowdin`](.github/workflows/Crowdin.yml) workflow uploads new English strings
to the project's Crowdin, and opens a `New translations from Crowdin` pull
request when translators add or update strings. To help translate, contribute
through the Crowdin project rather than opening a PR here.

## Changelog

We maintain a [CHANGELOG](docs/CHANGELOG.md) following the [Conventional 
Commits](https://www.conventionalcommits.org/) format. In order to update the 
[CHANGELOG](docs/CHANGELOG.md), run `task changelog` and commit the file.

## Secret scanning

CI runs [TruffleHog](https://github.com/trufflesecurity/trufflehog) against
every PR and every push to `main`, configured to **only fail on verified
secrets** (i.e., the credential is real and currently active). Compiled
binaries in the bundled Wine libraries trigger false positives on byte
patterns that match Box/Eraser/NPM token formats, but those are unverified
and ignored.

To scan locally before pushing:

```bash
brew install trufflehog
./scripts/scan-secrets.sh        # scans HEAD vs origin/main
./scripts/scan-secrets.sh main   # scans HEAD vs local main
```

If the scan fails on a real secret, **rotate the credential first** (treat
it as compromised), then remove it from history with
[`git filter-repo`](https://github.com/newren/git-filter-repo) or
[BFG](https://rtyley.github.io/bfg-repo-cleaner/) and force-push the fix
through a coordinated rewrite.

## Testing

### Running Tests

Whisky has two test layers:

**WhiskyKit unit tests** — the framework's pure-Swift logic, runnable
without launching the app:

```bash
swift test --package-path WhiskyKit
```

**WhiskyUITests** — XCUITest end-to-end coverage of the SwiftUI surface,
runnable from Xcode or via `xcodebuild`:

```bash
xcodebuild -project Whisky.xcodeproj \
  -scheme Whisky \
  -destination 'platform=macOS' \
  -only-testing:WhiskyUITests test
```

Tests that need bottle fixtures call `requireBottleFixture()`, which
`XCTSkip`s them when the user container has no bottles (always true on a
fresh CI runner). The fixture-free tests — the create-bottle sheet flow
and toolbar checks — run for real on every CI run. To exercise the
fixture-dependent tests locally, create at least one bottle in Whisky
before running the suite.

All tests must pass before your PR can be merged.

### Testing Launcher Compatibility Features

If your changes affect launcher compatibility (Issue #41), please perform the following tests:

1.  **Unit Tests**: Ensure coverage for launcher detection, environment generation, and settings persistence.
2.  **Manual Testing**:
    -   Create a test bottle (Windows 10).
    -   Enable Launcher Compatibility Mode.
    -   Verify detection and configuration for the target launcher.
    -   Check that settings persist after restart.

### Regression Testing

Before submitting a PR, verify no regressions:

```bash
# Run full test suite
swift test --package-path WhiskyKit

# Build Whisky app
xcodebuild -scheme Whisky -configuration Debug build

# Run UI tests (skip-aware on fresh containers)
xcodebuild -project Whisky.xcodeproj -scheme Whisky \
  -destination 'platform=macOS' \
  -only-testing:WhiskyUITests test

# Check formatting
swiftformat --lint .
```

## Review Process

Once your pull request passes CI checks (SwiftLint, SwiftFormat, and builds), it will be ready for review.

### Review Checklist

- [ ] All tests pass (`swift test --package-path WhiskyKit`)
- [ ] Build succeeds (`xcodebuild -scheme Whisky build`)
- [ ] SwiftFormat clean (`swiftformat --lint .`)
- [ ] SwiftLint clean (build shows no violations)
- [ ] Documentation updated (if adding features)

Thank you for contributing to Whisky!
