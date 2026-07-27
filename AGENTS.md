# AGENTS.md — guidance for AI agents and humans

This repository is designed so coding agents (Grok Build, Claude, Cursor, Codex, etc.) can extend Lyra safely.

## What Lyra is

Native **macOS-only** Markdown vault editor. Local folders of plain `.md` files. No Electron, no cloud sync, no database, no proprietary formats.

## Module map

```
Lyra/
  App/        # SwiftUI shell, open vault, NavigationSplitView, folder picker
  Vault/      # Scan tree, CRUD, bookmarks, wiki link resolution
  Editor/     # Source editing, TextKit highlight, autosave
  Preview/    # Live preview
  Models/     # VaultNode
  Scripts/    # smoke.sh (any OS), xcode-test.sh (Mac)
LyraTests/    # Unit tests for pure logic
docs/         # Architecture + design/plan specs
```

One primary type per file when practical. Keep files small.

## Invariants (do not break)

1. **Disk is source of truth** — notes are UTF-8 `.md` files; never invent a sidecar DB for v0.1.
2. **macOS only** — do not add iOS targets or multiplatform abstractions “just in case.”
3. **No Electron / no web-first UI** — SwiftUI + AppKit. WebKit preview only as a last-resort fallback, documented in `docs/architecture.md`.
4. **Sandbox-friendly** — security-scoped bookmarks for user-selected vault folders.
5. **YAGNI** — no plugins, graph view, sync, tags index, or theme marketplace unless a human explicitly asks.

## Coding standards

- Swift API Design Guidelines; prefer clarity over cleverness.
- UI state: `@MainActor` + `@Observable` stores/view models.
- File I/O: `async` off the hot path; don’t block the main thread on large trees.
- Prefer standard library / Apple frameworks before new dependencies.
- Match existing naming: `VaultStore`, `FileSystemVault`, `WikiLinkResolver`, `EditorViewModel`.

## How to add a feature

1. Read the v0.1 design/plan under `docs/superpowers/` if the change is large.
2. Put logic in the right folder (`Vault` vs `Editor` vs `Preview`).
3. Add unit tests in `LyraTests` for pure functions (paths, wiki resolve, naming).
4. **Always update `README.md`** for user-visible changes (features, install, build, version, screenshots, requirements). Treat README drift as a bug. Update `docs/architecture.md` when structure or invariants change.
5. Keep commits small and reviewable.

## Non-goals (v0.1)

Plugins, graph, full-text search index, cloud, accounts, iOS, line numbers, UI test suites.

## Testing

On a Mac:

```bash
xcodebuild -scheme Lyra -destination 'platform=macOS' test
```

Prefer tests for: wiki resolution, ignore rules, `Untitled` naming, file write helpers.

## Prefer the simplest working change

When in doubt: fewer files, fewer abstractions, less configuration. A later **ponytail**-style review will flag over-engineering.

## Git author identity (privacy)

**Never** put a personal/real email address in git commits, tags, or git config for this repo.

Use the GitHub noreply address only, for example:

```text
user.name  jackspiering
user.email 46534141+jackspiering@users.noreply.github.com
```

(Or the account’s `…@users.noreply.github.com` form from GitHub → Settings → Emails.)  
Configure this **locally** in the clone (`git config user.email …`); do not commit secrets or personal mailboxes.
