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

Unit tests live in `LyraTests/` (vault helpers, wiki links, naming, blocks, errors, editor durability).

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

## Manual smoke (v0.7)

Required (~10 minutes):

1. Open a vault with nested `.md` files
2. Sidebar shows folders + Markdown only (no `.git` / hidden)
3. **Source:** edit, wait ~1s, quit/reopen — content persisted
4. **⌘E** / segmented control: Source ↔ Reading; mode survives relaunch
5. **New Note (⌘N)** creates a file and **opens it in the editor** immediately
6. Create, rename, delete note and folder (rename without `.md` still keeps a Markdown file)
7. **Rename the open note**, keep typing, check Finder — exactly one file, with all your text
8. **Rename a folder** while a note inside it is open, keep typing and save — you must not get stuck
9. Selecting a **folder** does not close the open note
10. Edit a note, change the file on disk, type again → Keep Mine / Reload; **Cancel** pauses autosave (no dialog loop); **⌘Q** must not silently discard dirty work
11. Move or delete the open note in Finder, type again → **Note moved or deleted** warning (not silent recreate)
12. **⌘R** (Refresh Vault) after adding a file outside Lyra — it appears in the sidebar
13. **⌘S** saves immediately; failed save shows a plain-language alert and a toolbar indicator
14. **Export PDF…** with a long code fence and `**bold**` — multi-page PDF, bold not literal asterisks
15. Body text uses Inter; code fences stay monospaced
16. File → New Window opens another vault window; File menu has New Note / Open Vault / Refresh / Export

Optional:

17. `[[Other Note]]` opens from Reading when the file exists
18. **Source:** paste image → `_attachments/` + note-relative link; shows in Reading (pasting a browser URL must not hang on network)
19. Unreadable child folder in the vault — rest of the sidebar still appears
20. Eject/unplug the drive holding a dirty note — visible save failure, not silence

## License

Contributions are licensed under the MIT License.
