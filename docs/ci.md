# CI and releases

## Pull requests and `main`: `ci.yml`

| Job | Runner | What it does |
| --- | --- | --- |
| Smoke (structure) | Ubuntu | Runs `Scripts/smoke.sh`, then actionlint on the workflows |
| Detect app changes | Ubuntu | Skips the macOS job when nothing under `Lyra/`, `LyraTests/`, `Lyra.xcodeproj/`, `Scripts/`, or `.github/workflows/` changed |
| Build & test (macOS) | `macos-26`, Xcode 26 | Runs `Scripts/xcode-test.sh` with window snapshots |

**Smoke (structure)** and **Build & test (macOS)** are required checks on `main`; a
skipped job counts as passing. Keep those job names, or update branch protection with
them.

The macOS job pipes `xcodebuild` through xcbeautify, so compiler errors and failing tests
show up as PR annotations. It uploads the `lyra-snapshots` PNGs (kept 14 days) and, when
it fails, the `Lyra-xcresult` bundle (kept 7 days).

## Releases: `release.yml`

- Merging a `MARKETING_VERSION` bump to `main` builds the DMG, tags `v<version>`, and
  publishes a GitHub Release with the DMG and `SHA256SUMS.txt`. A project-file change
  without a bump does nothing.
- **Actions → Release → Run workflow** on `main` retries a release whose tag does not
  exist yet. On another branch, or for a version that is already released, it only
  uploads the DMG as the `Lyra-dmg` artifact.

`Scripts/package-dmg.sh` builds the Release configuration. It checks the signature, the
sandbox entitlements, and that the app version matches, then writes the DMG and its
checksum to `build/dist/`.

## Signing

Builds are ad-hoc signed (`CODE_SIGN_IDENTITY=-`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`)
so the App Sandbox applies. They are not Developer ID signed or notarized; that needs the
Apple Developer Program. Users get past the first-launch block with
**System Settings → Privacy & Security → Open Anyway**.

## Choices

- Actions are pinned to commit SHAs, and Dependabot opens one grouped update PR a month.
  actionlint is a checksum-verified release binary, not a third-party action.
- `GITHUB_TOKEN` is read-only in CI. Only the release workflow can write tags and releases.
- Warnings are errors. Swift 6 language mode is not enabled yet.
- No build cache: a full macOS run takes about two minutes.
- Snapshots render offscreen in the unit-test target, because macOS can't run in a
  container on non-Apple hardware. There are no pixel assertions and no UI test target.
