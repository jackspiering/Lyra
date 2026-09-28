# CI/CD

## Goals

1. Catch broken structure on every PR without a Mac (docs, entitlements, version consistency).
2. Build and unit-test the macOS app on a Mac runner.
3. Attach an ad-hoc-signed DMG on version tags (sandbox applied; not notarized).

## Pipelines

### PR / push — `.github/workflows/ci.yml`

| Job | Runner | What |
|-----|--------|------|
| `smoke` | `ubuntu-latest` | `Scripts/smoke.sh` (structure + `Scripts/lint.sh` whitespace and shell syntax checks) |
| `macos` | `macos-15` | `Scripts/xcode-test.sh` (Debug build + unit tests), in parallel with smoke |

| Setting | Value |
|---------|--------|
| Actions | `actions/checkout` pinned to the v7.0.1 commit SHA |
| Permissions | `contents: read` |
| Concurrency | cancel in-progress runs on the same ref |
| Timeouts | smoke 5m, macos 30m |

### Releases — `.github/workflows/release.yml`

A small `plan` job on Ubuntu decides what to do, so the macOS build only runs when there is something to ship.

| Trigger | What |
|---------|------|
| Push to `main` that changes the Xcode project | If `v<MARKETING_VERSION>` does not exist yet: build the DMG, create the tag on that commit, publish the GitHub Release. Otherwise nothing runs. |
| Push tag `v*` (e.g. `v0.12.0`) | Build the DMG and publish that tag's release |
| Manual **Run workflow** on `main` with a version | Same as a new version on `main`; fails if the tag already exists |
| Manual **Run workflow** without a version, or on another branch | DMG artifact only, no release |

A merged version bump (see [AGENTS.md](../AGENTS.md#shipping-a-change)) therefore releases itself. Tags the workflow creates use `GITHUB_TOKEN`, so they do not start a second run.

Version guard: the version must be three-part semver and match `MARKETING_VERSION` in the Xcode project. The packaging script also validates its output paths, checks `CFBundleShortVersionString` inside the built app, and refuses to package unless the finished app has a valid signature with the expected sandbox entitlements.

| Setting | Value |
|---------|--------|
| Actions | SHA-pinned `checkout` v7.0.1, `upload-artifact` v7.0.1, `softprops/action-gh-release` v3.0.3 |
| Checksums | SHA-256 of the DMG is written to `SHA256SUMS.txt` and included in the release notes |
| Permissions | `contents: write` (tags and releases) |
| Artifact retention | 14 days |
| Timeout | 45m |

Dependabot (`.github/dependabot.yml`) opens monthly PRs for GitHub Actions updates.

## Local

```bash
bash Scripts/smoke.sh
bash Scripts/xcode-test.sh                              # Mac + Xcode
VERSION=0.12.0 bash Scripts/package-dmg.sh              # → build/dist/Lyra-0.12.0.dmg
```

## Ship a DMG

1. Merge a PR that bumps `MARKETING_VERSION` (e.g. to `0.12.0`). The Release workflow tags `v0.12.0` and publishes it.
2. If that run was skipped or failed, start it again from **Actions → Release → Run workflow** on `main` with version `0.12.0` (works from a phone). Pushing the tag yourself also works:

```bash
git checkout main && git pull
git tag v0.12.0
git push origin v0.12.0
```

3. When **Actions → Release** is green, download `Lyra-0.12.0.dmg` from [Releases](https://github.com/jackspiering/Lyra/releases).

### Gatekeeper / signing

CI release builds are **ad-hoc signed** so App Sandbox entitlements are embedded. They are **not** Developer ID signed and **not notarized**. On macOS 15+, Control-click → Open is unreliable; use **System Settings → Privacy & Security → Open Anyway**, or build from source. Full notarization is a later step (Apple Developer Program).

### Signing flags in CI / package-dmg

```text
CODE_SIGN_IDENTITY=-
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
# CODE_SIGNING_ALLOWED must stay YES (default) so the signature (and sandbox) exist
```

### Compiler settings

Shared project configs set `SWIFT_TREAT_WARNINGS_AS_ERRORS` and `GCC_TREAT_WARNINGS_AS_ERRORS`. Swift 6 language mode / complete strict concurrency is intentionally **not** enabled yet (known deferred migration; current app has no live data races under normal use).

## Design notes (2026-07)

What we researched and intentionally chose:

| Topic | Choice | Why |
|-------|--------|-----|
| Checkout / artifacts | SHA-pinned v7.0.1 | Current maintained lines (`checkout` v7, `upload-artifact` v7); Node 20-era `@v4` is aging |
| Releases | SHA-pinned `softprops/action-gh-release` v3.0.3 | Replaces ad-hoc `gh release` shell; v2 unmaintained (Node 20 deprecation) |
| Runner | Keep **`macos-15`** | Matches deployment target (macOS 15+); `macos-26` exists but is unnecessary churn for now |
| Permissions | Read-only CI; write only on Release | Least privilege for `GITHUB_TOKEN` |
| Caching / lint matrix | Not added | Single target, small app; DerivedData cache is YAGNI until pain shows. A lightweight `Scripts/lint.sh` (trailing whitespace, final newline, and shell syntax) runs inside smoke; SwiftLint and multi-config lint matrices are still deferred |
| Action pins | Full commit SHAs with version comments | Release job has `contents: write`; Dependabot still opens PRs that bump the SHA + comment |
| Smoke script | Lean invariants, not every Swift path | macOS build is the compiler check; smoke covers docs/fonts/entitlements/version |

## Non-goals

- Publishing via GitHub Packages (use Releases + DMG)
- Multi-platform CI matrices
- Automatic version bumps without a human tag
- Notarization / Developer ID in CI (secrets + Apple program required)
- Building a DMG on every PR (release path only; version guards catch mismatch on tag)
