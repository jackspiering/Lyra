# CI/CD

## Goals

1. **Catch broken structure** on every PR without a Mac (file layout, Xcode project refs).
2. **Build and unit-test** the macOS app on a Mac runner.
3. Stay cheap and boring — no deploy pipeline until there is something to ship.

## Current pipeline

GitHub Actions (`.github/workflows/ci.yml`):

| Job | Runner | What |
|-----|--------|------|
| `smoke` | `ubuntu-latest` | `Scripts/smoke.sh` — required paths, pbxproj membership, entitlements, deployment target |
| `macos` | `macos-15` | `Scripts/xcode-test.sh` — `xcodebuild build test` (unsigned Debug) |

`macos` depends on `smoke` so a missing file fails fast before burning macOS minutes.

### Local

```bash
bash Scripts/smoke.sh                 # any OS
bash Scripts/xcode-test.sh            # Mac + Xcode only
```

## Signing in CI

Debug CI uses:

```text
CODE_SIGN_IDENTITY=-
CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO
```

Enough for compile + host unit tests. Distribution signing/notarization is **out of scope** until a release process exists.

## Roadmap (intentionally not built yet)

| Idea | When it earns its keep |
|------|------------------------|
| Tag → build `.app` / zip artifact | First public binary release |
| Notarization / Sparkle updates | Users install outside the App Store |
| SwiftLint | Style fights appear in review |
| SPM `LyraCore` + Linux tests | Pure logic grows and macOS CI is too slow/expensive |
| UI tests | Flows stabilize and regressions hurt |

## Non-goals

- Multi-platform matrices (iOS, etc.)
- Nightly fuzzing
- Automatic version bumping
- Deploying docs sites from CI (GitHub README is enough for v0.1)
