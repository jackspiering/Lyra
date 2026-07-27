# CI/CD

## Goals

1. **Catch broken structure** on every PR without a Mac (file layout, Xcode project refs).
2. **Build and unit-test** the macOS app on a Mac runner.
3. **Produce a downloadable DMG** on version tags (unsigned for now).

## Pipelines

### PR / push — `.github/workflows/ci.yml`

| Job | Runner | What |
|-----|--------|------|
| `smoke` | `ubuntu-latest` | `Scripts/smoke.sh` |
| `macos` | `macos-15` | `Scripts/xcode-test.sh` (Debug build + unit tests) |

### Tags — `.github/workflows/release.yml`

| Trigger | What |
|---------|------|
| Push tag `v*` (e.g. `v0.4.0`) | Release build → DMG → GitHub Release asset |
| Manual **workflow_dispatch** | Same DMG build; uploads an artifact (no Release unless you tagged) |

Local (Mac only):

```bash
bash Scripts/smoke.sh
bash Scripts/xcode-test.sh
VERSION=0.4.0 bash Scripts/package-dmg.sh   # → build/dist/Lyra-0.4.0.dmg
```

## How to ship a DMG

1. Merge version + release workflow to `main`.
2. Ensure marketing version in the project matches the tag (e.g. `0.4.0` ↔ `v0.4.0`).
3. Tag and push:

```bash
git checkout main && git pull
git tag v0.4.0
git push origin v0.4.0
```

4. Open **Actions → Release**; when green, download from the **Releases** page (`Lyra-0.4.0.dmg`).

### Gatekeeper note

CI builds are **unsigned / not notarized**. Testers may need right-click → **Open** the first time. Developer ID + notarization is a later step (Apple Developer Program).

## Signing in CI

```text
CODE_SIGN_IDENTITY=-
CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO
```

## Roadmap (later)

| Idea | When |
|------|------|
| Developer ID sign + notarize | Public installs without Gatekeeper friction |
| Sparkle auto-updates | Regular shipping cadence |
| SwiftLint | Style fights appear in review |
| SPM `LyraCore` + Linux tests | Pure logic grows |

## Non-goals

- GitHub Packages for the `.app` (use **Releases** + DMG)
- Multi-platform matrices
- Automatic version bumps without a human tag
