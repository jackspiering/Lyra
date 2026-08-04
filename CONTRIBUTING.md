# Contributing

## Setup

1. macOS 15+ and Xcode 16+
2. Clone the repo, open `Lyra.xcodeproj`
3. Scheme **Lyra** → Run

## Build and test

```bash
bash Scripts/smoke.sh          # structure checks (Linux/macOS)
bash Scripts/xcode-test.sh     # xcodebuild build + test (macOS)
```

Unit tests live in `LyraTests/` (vault helpers, wiki links, naming, block ranges, errors).

PRs run smoke on Ubuntu, then build/test on `macos-15`. Details: [docs/ci.md](docs/ci.md).

## Style

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- One main type per file when practical
- No drive-by refactors
- Read [AGENTS.md](AGENTS.md) for invariants

## Commits and PRs

- Prefer small commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`
- PR: what / why / how verified
- **Update `README.md`** for user-facing changes (features, install, version, shortcuts)
- Update `docs/architecture.md` when structure or invariants change
- Do not expand into plugins, sync, or non-macOS ports unless agreed

## Manual smoke (v0.5)

1. Open a vault with nested `.md` files
2. Sidebar shows folders + Markdown only (no `.git` / hidden)
3. **Source:** edit, wait ~1s, quit/reopen — content persisted
4. **⌘E** / segmented control: Source ↔ Reading; mode survives relaunch
5. **Source:** click in the note — blinking caret; type — content updates
6. Create, rename, delete note and folder (rename without `.md` still keeps a Markdown file)
7. Selecting a **folder** does not close the open note
8. `[[Other Note]]` opens from Reading when the file exists
9. **Source:** paste image → `_attachments/` + note-relative link; shows in Reading
10. **Export PDF…** from each mode
11. **⌘S** saves immediately
12. Edit a note, change the file on disk (e.g. another editor), type again → Keep Mine / Reload dialog
13. A failed save/paste shows a plain-language alert (not raw Cocoa codes)
14. Body text uses Inter; code fences stay monospaced
15. No File → New Window (single main window)

## License

Contributions are licensed under the MIT License.
