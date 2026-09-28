## Summary

<!-- What changed and why (1–3 bullets). -->

## Test plan

- [ ] `bash Scripts/smoke.sh` passes
- [ ] GitHub Actions **Smoke (structure)** is green
- [ ] GitHub Actions **Build & test (macOS)** is green
- [ ] UI changes: checked the `lyra-snapshots` artifact (Night and Parchment)
- [ ] On a Mac (optional for docs-only): open vault → edit → save → switch Source/Reading

## Notes

CI: `.github/workflows/ci.yml` (read-only). Releases/DMG: `.github/workflows/release.yml` publishes when a version bump merges to `main` (or on `v*` tags).
