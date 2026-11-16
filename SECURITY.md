# Security

## Supported versions

Only the [latest release](https://github.com/jackspiering/Lyra/releases/latest) gets fixes.

## Reporting a vulnerability

Please report it privately, not in a public issue: open the repository's **Security** tab
and choose **Report a vulnerability**, or go to
<https://github.com/jackspiering/Lyra/security/advisories/new>.

A good report has the Lyra version, the macOS version, and the smallest vault or note
that shows the problem.

## What counts

A vault can come from someone else: a shared folder or a cloned repository. Reports are
welcome for anything that lets such a vault make Lyra read or write files outside the
vault folder, run code, launch other apps, or fetch from the network without a click.
Problems in the release workflow or the published DMG count too.

Releases are ad-hoc signed and not notarized (see [docs/ci.md](docs/ci.md)). That is a
known limit, not a vulnerability.
