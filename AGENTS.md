# AGENTS.md — guidance for AI agents and humans

This repository is designed so coding agents can extend Lyra safely.

## What Lyra is

Native **macOS-only** Markdown vault editor. Local folders of plain `.md` files. No Electron, no cloud sync, no database, no proprietary formats.

## Module map

```
Lyra/
  App/        # Shell, open vault, theme, Inter fonts, UserFacingError, NoteViewMode
  Vault/      # Tree scan, CRUD, bookmarks, wiki resolve, AttachmentStore
  Editor/     # TextKit source, highlight, autosave, image paste
  Preview/    # Block parse, Reading / Live Preview, PDF export
  Models/     # VaultNode
  Resources/  # Assets, Fonts (Inter + OFL)
  Scripts/    # smoke.sh (any OS), xcode-test.sh (Mac)
LyraTests/    # Pure logic unit tests
docs/         # architecture, CI, design specs
```

One primary type per file when practical. Keep files small.

## Invariants (do not break)

1. **Disk is source of truth** — UTF-8 `.md` files; no sidecar DB.
2. **macOS only** — no iOS targets or multiplatform abstractions “just in case.”
3. **No Electron / no web-first UI** — SwiftUI + AppKit. WebKit only as a last-resort fallback, documented in `docs/architecture.md`.
4. **Sandbox-friendly** — security-scoped bookmarks for user-selected vault folders.
5. **YAGNI** — no plugins, graph view, sync, tags index, or theme marketplace unless a human explicitly asks.

## Coding standards

- Swift API Design Guidelines; clarity over cleverness.
- UI state: `@MainActor` + `@Observable` stores/view models.
- File I/O: don’t block the main thread on large trees.
- Prefer standard library / Apple frameworks before new dependencies.
- Match existing naming: `VaultStore`, `FileSystemVault`, `WikiLinkResolver`, `EditorViewModel`, `UserFacingError`, `LyraFonts`.
- User-visible failures go through `UserFacingError` + `VaultStore.present…`, not raw domain strings.

## How to add a feature

1. Read the relevant design under `docs/superpowers/` if the change is large.
2. Put logic in the right folder (`Vault` vs `Editor` vs `Preview` vs `App`).
3. Add unit tests in `LyraTests` for pure functions (paths, wiki resolve, naming, ranges, errors).
4. **Always update `README.md`** for user-visible changes. Update `docs/architecture.md` when structure or invariants change.
5. Keep commits small and reviewable.

## Non-goals

Plugins, graph, full-text search index, cloud, accounts, iOS, full WYSIWYG, UI test suites (unless asked).

## Testing

On a Mac:

```bash
xcodebuild -scheme Lyra -destination 'platform=macOS' test
# or
bash Scripts/xcode-test.sh
```

Prefer tests for: wiki resolution, ignore rules, `Untitled` naming, attachment helpers, block ranges, error copy.

## Prefer the simplest working change

When in doubt: fewer files, fewer abstractions, less configuration. A **ponytail**-style review will flag over-engineering.

## Git author identity (privacy)

**Never** put a personal/real email address in git commits, tags, or git config for this repo.

Use the GitHub noreply address only, for example:

```text
user.name  jackspiering
user.email 46534141+jackspiering@users.noreply.github.com
```

Configure this **locally** in the clone; do not commit secrets or personal mailboxes.
