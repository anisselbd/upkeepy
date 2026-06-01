# Security Policy

## Supported Versions

UpKeepy is currently at v1. Security fixes are applied to the latest version on
the `main` branch.

| Version | Supported |
| ------- | --------- |
| 1.x     | ✅        |

## Reporting a Vulnerability

If you discover a security issue in UpKeepy, please report it privately rather
than opening a public issue.

- Use GitHub's **[private vulnerability reporting](https://github.com/anisselbd/upkeepy/security/advisories/new)** (Security tab → Report a vulnerability), or
- Open a regular issue for non-sensitive concerns: https://github.com/anisselbd/upkeepy/issues

Please include:

- A description of the issue and its potential impact.
- Steps to reproduce, if applicable.
- The macOS version and UpKeepy version you tested.

You can expect an initial response within a few days. Confirmed issues will be
addressed as quickly as is reasonable for a solo-maintained project, and credit
will be given to reporters who wish to be acknowledged.

## Scope and Design Notes

UpKeepy runs local package-manager commands (`brew`, `npm`, `gem`,
`softwareupdate`) on your machine, with the same privileges as your user
account. It does not phone home, collect telemetry, or transmit any data over
the network beyond what those tools themselves do when fetching updates.

Because the app shells out to these tools, the most relevant security surface is
the construction of those commands. Review of that logic lives in
`Sources/UpKeepy/Shell.swift` and `Sources/UpKeepy/MaintenanceEngine.swift`.
