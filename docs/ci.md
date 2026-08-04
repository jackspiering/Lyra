# CI/CD

## Goals

1. Catch broken structure on every PR without a Mac (docs, entitlements, version consistency).
2. Build and unit-test the macOS app on a Mac runner.
3. Attach an ad-hoc-signed DMG on version tags (sandbox applied; not notarized).

## Pipelines

### PR / push — `.github/workflows/ci.yml`

| Job | Runner | What |
|-----|--------|------|
| `smoke` | `ubuntu-latest` | `Scripts/smoke.sh` |
| `macos` | `macos-15` | `Scripts/xcode-test.sh` (Debug build + unit tests), after smoke |

| Setting | Value |
|---------|--------|
| Actions | `actions/checkout@v7` |
| Permissions | `contents: read` |
| Concurrency | cancel in-progress runs on the same ref |
| Timeouts | smoke 5m, macos 30m |

### Tags — `.github/workflows/release.yml`

| Trigger | What |
|---------|------|
| Push tag `v*` (e.g. `v0.8.0`) | Release build → DMG → GitHub Release asset |
| Manual **workflow_dispatch** | Same DMG build; artifact only (no Release unless tagged) |

Version guard: the tag (or dispatch input) must be three-part semver and match `MARKETING_VERSION` in the Xcode project. The packaging script also checks `CFBundleShortVersionString` inside the built app.

| Setting | Value |
|---------|--------|
| Actions | `checkout@v7`, `upload-artifact@v7`, `softprops/action-gh-release@v3` |
| Permissions | `contents: write` (releases only) |
| Artifact retention | 14 days |
| Timeout | 45m |

Dependabot (`.github/dependabot.yml`) opens monthly PRs for GitHub Actions updates.

## Local

```bash
bash Scripts/smoke.sh
bash Scripts/xcode-test.sh                              # Mac + Xcode
VERSION=0.8.0 bash Scripts/package-dmg.sh               # → build/dist/Lyra-0.8.0.dmg
```

## Ship a DMG

1. Merge to `main` with marketing version matching the intended tag (`0.8.0`).
2. Tag and push:

```bash
git checkout main && git pull
git tag v0.8.0
git push origin v0.8.0
```

3. When **Actions → Release** is green, download `Lyra-0.8.0.dmg` from [Releases](https://github.com/jackspiering/Lyra/releases).

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
| Checkout / artifacts | `@v7` majors | Current maintained lines (`checkout` v7, `upload-artifact` v7); Node 20-era `@v4` is aging |
| Releases | `softprops/action-gh-release@v3` | Replaces ad-hoc `gh release` shell; v2 unmaintained (Node 20 deprecation) |
| Runner | Keep **`macos-15`** | Matches deployment target (macOS 15+); `macos-26` exists but is unnecessary churn for now |
| Permissions | Read-only CI; write only on Release | Least privilege for `GITHUB_TOKEN` |
| Caching / lint matrix | Not added | Single target, small app; DerivedData cache and SwiftLint are YAGNI until pain shows |
| Action pins | Floating major tags (`@v7`, `@v3`) | Dependabot bumps majors; avoid fragile full SHAs without automation |
| Smoke script | Lean invariants, not every Swift path | macOS build is the compiler check; smoke covers docs/fonts/entitlements/version |

## Non-goals

- Publishing via GitHub Packages (use Releases + DMG)
- Multi-platform CI matrices
- Automatic version bumps without a human tag
- Notarization / Developer ID in CI (secrets + Apple program required)
- Building a DMG on every PR (release path only; version guards catch mismatch on tag)
