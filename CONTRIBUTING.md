# Contributing to Lyra

Thanks for helping improve Lyra.

## Development setup

1. macOS 15+ and Xcode 16+
2. Clone the repo and open `Lyra.xcodeproj`
3. Select scheme **Lyra** → Run

## Building and testing

```bash
xcodebuild -scheme Lyra -destination 'platform=macOS' build
xcodebuild -scheme Lyra -destination 'platform=macOS' test
```

Unit tests live in `LyraTests/` and target pure logic (vault helpers, wiki links, naming).

## Style

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Keep types focused; one main type per file when practical
- No drive-by refactors unrelated to your change
- Read [AGENTS.md](AGENTS.md) for architecture invariants

## Commits and PRs

- Prefer small commits with conventional-ish prefixes: `feat:`, `fix:`, `docs:`, `test:`, `chore:`
- PR description: what changed, why, how you verified
- Do not expand scope into plugins, sync, or non-macOS ports unless agreed

## Manual smoke checklist (v0.1)

1. Open a folder with nested `.md` files as a vault
2. Sidebar shows folders and markdown only; ignores `.git` / hidden files
3. Edit a note; wait ~1s; quit and reopen — content persisted
4. Toggle preview (⌘⇧P)
5. Create, rename, and delete a note (and a folder)
6. Add `[[Other Note]]` where `Other Note.md` exists; open via preview link if supported

## License

By contributing, you agree that your contributions are licensed under the MIT License.
