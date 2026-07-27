# CI/CD

## Goals

1. Catch broken structure on every PR without a Mac (layout, Xcode project refs).
2. Build and unit-test the macOS app on a Mac runner.
3. Attach an unsigned DMG on version tags.

## Pipelines

### PR / push — `.github/workflows/ci.yml`

| Job | Runner | Command |
|-----|--------|---------|
| `smoke` | `ubuntu-latest` | `Scripts/smoke.sh` |
| `macos` | `macos-15` | `Scripts/xcode-test.sh` (Debug + unit tests) |

### Tags — `.github/workflows/release.yml`

| Trigger | Result |
|---------|--------|
| Push tag `v*` (e.g. `v0.5.0`) | Release build → DMG → GitHub Release asset |
| Manual **workflow_dispatch** | Same DMG build as an Actions artifact (no Release unless tagged) |

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

## Non-goals

- Publishing the app via GitHub Packages (use Releases + DMG)
- Multi-platform CI matrices
- Automatic version bumps without a human tag
