# CI/CD

## Goals

1. Catch broken structure on every PR without a Mac (layout, Xcode project refs).
2. Build and unit-test the macOS app on a Mac runner.
3. Attach an unsigned DMG on version tags.

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
| Push tag `v*` (e.g. `v0.5.0`) | Release build → DMG → GitHub Release asset |
| Manual **workflow_dispatch** | Same DMG build; artifact only (no Release unless tagged) |

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
VERSION=0.5.0 bash Scripts/package-dmg.sh               # → build/dist/Lyra-0.5.0.dmg
```

## Ship a DMG

1. Merge to `main` with marketing version matching the intended tag (`0.5.0`).
2. Tag and push:

```bash
git checkout main && git pull
git tag v0.5.0
git push origin v0.5.0
```

3. When **Actions → Release** is green, download `Lyra-0.5.0.dmg` from [Releases](https://github.com/jackspiering/Lyra/releases).

### Gatekeeper

CI builds are **unsigned / not notarized**. Testers may need right-click → **Open** the first time. Developer ID + notarization is a later step (Apple Developer Program).

### Signing flags in CI

```text
CODE_SIGN_IDENTITY=-
CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO
```

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

## Non-goals

- Publishing via GitHub Packages (use Releases + DMG)
- Multi-platform CI matrices
- Automatic version bumps without a human tag
- Notarization / Developer ID in CI (secrets + Apple program required)
