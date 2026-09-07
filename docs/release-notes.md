Makes the end-of-operation summary actually show why an update failed.

## Install

```bash
brew install --cask anisselbd/tap/upkeepy
```

Already installed? `brew upgrade --cask upkeepy`. Requires macOS 14 or later.

## Fix

Updating everything at once kept only the **names** of the packages that failed,
so the summary read `Failed: node-sass` and nothing more. The diagnosis was
thrown away: target version against installed version, the likely cause, and the
command to run. It was still available when updating a single package, but
"Update all" is the path most people take, and it is exactly where a failure
needs explaining.

The summary now keeps the log of every failed package, each under its own
heading. Two things the README promises hold on that path again: a detail view
you can expand and copy, and a banner that names the likely cause.

Also trims the blank space left under a one-line summary.

## Previously, in 1.1.0

A demo mode (⏰ footer menu) that shows a simulated set of pending updates and
ghost casks, for screenshots and demos, without running any command. Plus a fix
for the expandable log that would not expand at all.
