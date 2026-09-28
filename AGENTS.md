# AGENTS.md

Guidance for coding agents (and humans) working on Lyra. Read this first, then
[`docs/architecture.md`](docs/architecture.md) for the decision log.

## What Lyra is

A native **macOS-only** notes app over a folder of Markdown. Writing comes first;
wiki links, backlinks, and in-memory search exist so someone can leave Obsidian
without Electron. Notes are plain UTF-8 `.md` files. A note’s identity is its
**filename** — the first `#` heading is just content.

## Commands

| What | Command | Where |
| --- | --- | --- |
| Structure, docs, version, whitespace | `bash Scripts/smoke.sh` | Any OS |
| Whitespace / shell lint only | `bash Scripts/lint.sh` | Any OS |
| Build + unit tests | `bash Scripts/xcode-test.sh` | macOS + Xcode 16 |

There is no Swift toolchain on Linux for this app. If you are not on a Mac, the
`Build & test (macOS)` CI job is your compiler: push, then read its log. Write
Swift that type-checks on the first try — annotate closure and collection types
instead of leaning on inference in large literals.

## Hard rules

1. **Disk is the source of truth.** No sidecar database or persisted index.
   In-memory maps rebuilt on scan are fine.
2. **macOS only**, SwiftUI + AppKit. No iOS targets, no Electron, no WebKit in the
   default path.
3. **Sandbox-friendly.** Vault access goes through security-scoped bookmarks.
4. **Plain text in the editor.** Source styles Markdown but never hides or rewrites
   it. Reading is not editable. No WYSIWYG.
5. **Stay small.** Out of scope unless a human asks: plugins, graph view, sync,
   accounts, tag index, daily notes, frontmatter UI, `![[embeds]]`,
   `[[Note#heading]]`, theme picker or marketplace, UI test suites.
6. **Privacy in git.** Never commit a personal email. Use the GitHub noreply
   address (`46534141+jackspiering@users.noreply.github.com`), set locally.

## Where code goes

```
Lyra/
  App/        Window shell, tabs, sidebar, inspector, settings, theme, fonts, errors
  Vault/      Scan, CRUD, bookmarks, wiki resolve + backlinks, search, attachments
  Editor/     NSTextView source editor, highlighter, autosave, paste
  Preview/    Reading blocks, images, PDF export
  Models/     Shared value types (VaultNode)
LyraTests/    XCTest unit tests for pure logic
Scripts/      smoke, lint, xcode-test, package-dmg
docs/         architecture decisions, CI, design mockups
```

- One primary type per file when practical; keep files small.
- **New Swift files must be registered in `Lyra.xcodeproj/project.pbxproj`**
  (file reference, group, and build phase). The project does not use synchronized
  folders, so an unregistered file silently won’t compile. Prefer extending an
  existing file when the addition is small.
- `App/` may depend on `Vault/`; `Vault/` must not depend on `App/` views.

## Conventions

- Swift API Design Guidelines; clarity over cleverness.
- UI state is `@MainActor` + `@Observable`. Don’t block the main thread with file I/O
  on large trees.
- Apple frameworks before new dependencies (there are none today — keep it that way).
- User-visible failures go through `UserFacingError` and `VaultStore.present…`.
- Match existing names: `VaultStore`, `FileSystemVault`, `WikiLinkResolver`,
  `EditorViewModel`, `UserFacingError`, `LyraFonts`, `LyraTheme`.

## Look and feel

The visual system lives in two files. Use them instead of hard-coded values.

- **`LyraTheme`** — colors for the two built-in looks, *Night* (dark) and
  *Parchment* (light), that follow the system appearance: surfaces (`paper`,
  `chrome`, `sidebar`, `fill`, `hairline`), text (`ink`, `markup`), `accent`
  (gold / bronze-gold), and Markdown tokens. It also owns the writing column
  (`columnWidth`, `columnMargin`, `columnInset(forWidth:)`) shared by the title,
  Source, and Reading.
- **`LyraFonts`** — bundled Inter at fixed sizes: `prose` (16pt, 7pt line spacing)
  for writing, `label`/`caption` for chrome, `title` for the note name,
  `headingSize(level:)` shared by Source and Reading.

Avoid system gray backgrounds (`.bar`, `windowBackgroundColor`) in the vault
window; they break the palette. Reference mockups: `docs/design/`.

## Tests

Add XCTest cases in `LyraTests/` for pure functions: path and wiki resolution,
aliases, backlink context, naming, ranges, highlighter attributes, error copy.
Extend an existing test file when one fits (new files need pbxproj entries too).
Views are verified by hand on a Mac — note what you could not check in the PR.

## Shipping a change

1. Keep the change focused; small commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
2. **Update `README.md`** for anything a user can see.
3. Update `docs/architecture.md` when structure, invariants, or a recorded
   decision changes.
4. Run `bash Scripts/smoke.sh`; on a Mac also `bash Scripts/xcode-test.sh`.
5. PR description: what, why, how verified, and what still needs a manual look.

When in doubt, choose fewer files, fewer abstractions, and less configuration.
