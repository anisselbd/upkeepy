First public release. UpKeepy is a macOS menu bar app that keeps Homebrew, npm,
RubyGems and macOS itself up to date, without opening a terminal.

**Signed and notarized by Apple**, so it opens without a Gatekeeper warning.
2 MB, no dependencies, no telemetry, no account.

## Install

```bash
brew install --cask anisselbd/tap/upkeepy
```

Or download the `.dmg` below and drag UpKeepy to Applications.

Requires macOS 14 (Sonoma) or later.

## What it does

- **One popover for four package managers.** Homebrew formulae and casks, global
  npm packages, gems, and macOS system updates, in a single list.
- **Ghost cask detection.** Finds apps Homebrew still believes are installed but
  that were dragged to the trash by hand, and offers to reinstall them or drop
  the dangling reference. `brew` itself cannot do this.
- **Fake npm successes, exposed.** npm exits 0 even when a native module failed
  to compile. UpKeepy runs a post-install check and tells you when an update
  only *looks* successful.
- **Update one package or everything**, with live shell output rather than a
  fake progress bar, and an honest summary at the end: what worked, what failed,
  how long it took, with an expandable log you can copy.
- **Background checks** every 30 min to 24 h, with a notification when something
  new shows up.

## Notes

The app is deliberately not sandboxed: driving `brew`, `npm` and `gem` means
writing outside a sandbox container. That is also why it ships outside the Mac
App Store. The source is MIT licensed and readable in full.
