Adds a demo mode, and fixes an expandable log that would not expand.

## Install

```bash
brew install --cask anisselbd/tap/upkeepy
```

Already installed? `brew upgrade --cask upkeepy`. Or download the `.dmg` below
and drag UpKeepy to Applications. Requires macOS 14 (Sonoma) or later.

## Demo mode

A toggle in the ⏰ footer menu shows a simulated set of pending updates and
ghost casks, independently of what your machine actually has. It exists because
a well-kept Mac has nothing to show, and above all no ghost casks, which makes
the app impossible to demo or screenshot honestly.

- Eight packages across all four managers, two ghost casks, one macOS update.
- Simulated operations replay real output line by line, so the progress bar,
  the live output and the end summary behave exactly as they do for real.
- One npm package fails on purpose, reproducing the fake-success diagnosis:
  target version, installed version, mismatch, likely cause, and the command
  to fix it.
- **No command is run while demo mode is on.** It never touches your packages,
  which makes it safe on a machine you do not own.
- A DEMO badge stays visible in the header, so a simulated state can never be
  mistaken for your machine's real one.

## Fix

The expandable detail view of the end-of-operation summary did not open. The
chevron moved a few pixels and showed nothing, which made the failure log
unreadable, exactly when it matters most. Inside a `MenuBarExtra(.window)` on
the macOS 26 SDK, a `ScrollView` given only a `maxHeight` collapses to its
ideal size; it now gets an explicit measured height, like the main list already
did.
