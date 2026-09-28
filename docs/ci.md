# CI/CD

## Goals

1. Catch broken structure on every PR without a Mac (docs, entitlements, version consistency, shell and workflow lint).
2. Build and unit-test the macOS app on a Mac runner, and show what the UI looks like.
3. Attach an ad-hoc-signed DMG on version tags (sandbox applied; not notarized).

## Pipelines

### PR / push — `.github/workflows/ci.yml`

| Job | Runner | What |
|-----|--------|------|
| `smoke` | `ubuntu-latest` | `Scripts/smoke.sh` (structure + `Scripts/lint.sh`: whitespace, shell syntax, ShellCheck), then actionlint on the workflows |
| `changes` | `ubuntu-latest` | Diffs the PR (or push) against its base. Outputs `app=false` when nothing under `Lyra/`, `LyraTests/`, `Lyra.xcodeproj/`, `Scripts/`, or `.github/workflows/` changed |
| `macos` | `macos-26` (Xcode 26) | `Scripts/xcode-test.sh` (Debug build + unit tests). Skipped for docs-only changes; a skipped job still satisfies a required check. Runs in parallel with smoke |

The macOS job also:

- pipes the build through `xcbeautify`, so compiler errors and failing tests show as annotations on the PR;
- writes a test summary (passed, failed, skipped, and each failure) to the run page;
- renders window snapshots (`TEST_RUNNER_LYRA_SNAPSHOTS=1`, see `LyraTests/WindowSnapshotTests.swift`) and uploads them as the `lyra-snapshots` artifact;
- uploads the `.xcresult` bundle when the job fails.

| Setting | Value |
|---------|--------|
| Actions | `checkout` and `upload-artifact` pinned to v7.0.1 commit SHAs |
| actionlint | v1.7.12 release binary, verified against its SHA-256 (no third-party action) |
| Permissions | `contents: read` |
| Concurrency | a newer push cancels a pull request's running checks; runs on `main` are never cancelled |
| Timeouts | smoke 5m, changes 5m, macos 30m |
| Artifacts | `lyra-snapshots` 14 days; `Lyra-xcresult` (failures only) 7 days |

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

Dependabot (`.github/dependabot.yml`) opens one grouped PR a month for GitHub Actions updates.

## Local

```bash
bash Scripts/smoke.sh
bash Scripts/xcode-test.sh                              # Mac + Xcode
RESULT_BUNDLE=build/Lyra.xcresult bash Scripts/xcode-test.sh   # keep an .xcresult
TEST_RUNNER_LYRA_SNAPSHOTS=1 bash Scripts/xcode-test.sh # also render window PNGs
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
| Runner | **`macos-26`** with its default Xcode 26 (from 0.13) | macOS 26 is current; building with its SDK gives Liquid Glass on macOS 26 while the app still deploys to macOS 15. The app compiled unchanged with warnings as errors |
| Permissions | Read-only CI; write only on Release | Least privilege for `GITHUB_TOKEN` |
| Caching / lint matrix | Not added | Single target, small app; a full macOS run takes about two minutes, so a DerivedData cache is YAGNI until pain shows. `Scripts/lint.sh` (trailing whitespace, final newline, shell syntax, ShellCheck) and actionlint run inside smoke; SwiftLint and multi-config lint matrices are still deferred |
| Docs-only changes | `changes` job gates the macOS job | Skips a macOS build when no code, test, script, or workflow file changed; `if:` skipping keeps required checks green |
| Logs | `xcbeautify` (preinstalled on the runner) | Short logs plus PR annotations; `LYRA_RAW_LOG=1` prints raw `xcodebuild` output |
| UI preview | Offscreen snapshots in the unit-test target | macOS cannot run in Docker on non-Apple hardware and Apple's `container` runs Linux, so the macOS runner renders the UI instead. No UI test target and no pixel assertions |
| Action pins | Full commit SHAs with version comments | Release job has `contents: write`; Dependabot still opens PRs that bump the SHA + comment |
| Smoke script | Lean invariants, not every Swift path | macOS build is the compiler check; smoke covers docs/fonts/entitlements/version |

## Non-goals

- Publishing via GitHub Packages (use Releases + DMG)
- Multi-platform CI matrices
- Automatic version bumps without a human tag
- Notarization / Developer ID in CI (secrets + Apple program required)
- Building a DMG on every PR (release path only; version guards catch mismatch on tag)
