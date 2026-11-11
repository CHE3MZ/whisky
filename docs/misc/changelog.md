## What's Changed
* feat: fully replaced the runtime assembler with a new script that reads sources.yml by @CHE3MZ
* ci: added local taskfile jobs for local side dev ops by @CHE3MZ
* ci: moved secret scans to task instead of having a dedicated script for it by @CHE3MZ
* ci: added a report script to generate dependencies.md dynamically by @CHE3MZ
* ci: moved a few files around for better fs structure by @CHE3MZ
* ci: added a tests folder and moved the audio test there by @CHE3MZ
* ci: moved auditing scripts to scripts/audit by @CHE3MZ
* ci: updated upstream tracking action to use a better scripting based format for easier edits by @CHE3MZ
* feat: breaking, removed discord badge/banner display support for privacy and maintenance reasons by @CHE3MZ
* docs: cleaned up the images folder and moved it into docs/assets by @CHE3MZ
* ci: update homebrew tap workflow to add guardrails by @CHE3MZ
* feat: breaking, changed the sparkle key and moved appcast to automations by @CHE3MZ
* ci: changed the release workflow to automate versioning by @CHE3MZ
* ci: added a build script and build task for a better local building experience by @CHE3MZ
* fix: patched issues caught by swiftformat and swiftlint by @CHE3MZ
* feat: added create-dmg to the project for cleaner dmg creation by @CHE3MZ
* fix: fully removed telemetry and anonymous usage data collection, this is a semi-breaking change by @CHE3MZ
* fix: breaking, changed the default write paths from bundle identifier and containers to "Whisky" by @CHE3MZ
* fix: breaking, migrated to my own bundle identifier at com.che3mz.whisky by @CHE3MZ
* fix: swapped to my own developer team ID in place of the template by @CHE3MZ
* fix: patched incorrect developer token references and missing devtool entries by @CHE3MZ
* fix: make scripts chmod executable by @CHE3MZ
* fix: updated broken/incorrect link references by @CHE3MZ
* fix: restore app-v tag format for app releases by @CHE3MZ
* fix: breaking, swapped the remote homebrew tap to mine at CHE3MZ/homebrew-tools by @CHE3MZ
* fix: breaking, changed the project ownership to my repo at CHE3MZ/whisky by @CHE3MZ
* chore: removed nix flake in favor of brewfile by @CHE3MZ
* chore: removed unneeded stuff by @CHE3MZ
* docs: fixed a few broken link references by @CHE3MZ
* docs: changed git cliff format and generated the first changelog by @CHE3MZ
* docs: changed the changelog format and added a taskfile by @CHE3MZ
* init by @CHE3MZ

### New Contributors
* @CHE3MZ made their first contribution

