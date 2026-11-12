# Distribution & discoverability playbook

The hard part of "becoming the main release" isn't code. It's that someone who googles *"Whisky
mac"* today lands on the **archived original** (getwhisky.app, `whisky-app/whisky`, and the default
`brew install --cask whisky` cask), not this fork. These are the concrete, mostly-external steps to
close that gap. Most require a real account or a third-party PR, so they're listed here as ready-to-run
actions rather than automated.

## 1. Homebrew (highest leverage)

The default `brew install --cask whisky` installs the archived `IsaacMarovitz/Whisky` v2.3.5. The good
news: the homebrew-cask `whisky` cask is **already `deprecate!`d** (date `2025-04-09`, reason
`unmaintained`), so `brew install --cask whisky` already prints a deprecation warning, so it isn't a fully
silent dead install. But it still installs v2.3.5, its `homepage` still points at getwhisky.app, and
there's no pointer to this fork.

**Action:** open a PR against [homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) to add
a successor pointer. Realistic asks, easiest first:

!!! quote "Requested cask change"
    The `whisky` cask is already deprecated (unmaintained, 2025-04-09). `CHE3MZ/whisky` is an actively
    maintained fork (signed + notarized DMGs, in-app Sparkle updates). Requesting one of:
    (a) add a `caveats` note pointing users to `brew install --cask CHE3MZ/tools/whisky`;
    (b) repoint the cask's `url`/`homepage` to the fork's releases; or
    (c) `disable!` the cask with that pointer.

The `caveats`-pointer ask (a) is the lowest-friction and most likely to be accepted; a full repoint (b)
is more sensitive. Until then, keep the README's "Getting the right Whisky" warning prominent and the
qualified tap (`CHE3MZ/tools/whisky`) as the documented path.

## 2. Search & domain

- The GitHub Pages landing page (`docs/index.md` and `docs/site/overrides/home.html`) already has solid
  on-page SEO (title, description, OpenGraph/Twitter cards, JSON-LD). The ceiling is **domain
  authority**: `che3mz.github.io` is treated as its own site by search engines (github.io is on the
  Public Suffix List), but a project subpath on a personal Pages domain still carries less weight for a
  niche query than a dedicated domain with backlinks.
- **Action:** consider a custom domain (e.g. `whisky.example.com` or a `.app`) with a `CNAME` in
  `docs/` and the Pages custom-domain setting. Marginal alone (~5-10%), meaningful **only** paired
  with backlinks below.
- **Action:** ask the archived `whisky-app` org (Isaac) whether the archived repo's README / getwhisky.app
  can carry a one-line "no longer maintained, see CHE3MZ/whisky" pointer. A single backlink from the
  canonical domain is worth more than any on-page tweak.

## 3. Community presence (backlinks + word of mouth)

The macOS-gaming audience lives in a few places. Seeding them is the cheapest real discoverability win:

- **AppleGamingWiki:** Whisky is referenced on game pages but has no dedicated, fork-aware page.
  Create/claim one that names this fork as the maintained Whisky.
- **r/macgaming, r/macapps:** a single honest "the original Whisky was archived; I've been maintaining a
  fork" post (link the migration wizard, `File → Migrate from the Original Whisky`, which makes switching
  one click). Don't spam; one good post + answering replies.

## 4. Lower the switching cost

- One-click **File → Migrate from the Original Whisky** imports the original app's bottles in place
  (shipped in 3.1.0).
- Lead with that in any launch post: "keep your existing bottles, one click" is the message that
  converts archived-app users.

## What's explicitly *not* in scope here

- App Store distribution is impossible. Wine needs JIT, full process control, and unsandboxed file
  access, all blocked by the App Store sandbox. GitHub Releases + Homebrew tap is the ceiling.
