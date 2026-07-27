# Architecture

Lyra is a single macOS app target with module-shaped source folders. This document records the decisions that keep the app small and local-first.

## Decision: plain files on disk

**Choice:** The vault is a normal directory tree. Notes are UTF-8 `.md` files.

**Why:** Zero lock-in, trivial backup/git, easy for tools and AI agents to read. No SQLite or proprietary package format in v0.1.

**Consequence:** The file tree is refreshed from disk after mutations. There is no separate index DB.

## Decision: single Xcode app target + module folders

**Choice:** One `Lyra` app target; code grouped as `App/`, `Vault/`, `Editor/`, `Preview/`, `Models/`.

**Why:** Real macOS app (sandbox, menus, TextKit) with clear boundaries. Avoids premature SPM split.

**Consequence:** Later extraction into packages is possible without a rewrite if folders stay clean.

## Decision: TextKit source editor

**Choice:** Markdown source editing via AppKit `NSTextView` wrapped in `NSViewRepresentable` (`MarkdownTextView`), with a simple regex-based highlighter (`MarkdownHighlighter`) for v0.1.

**Why:** Native performance and feel; better long-term control than a WebView editor.

## Decision: native preview first

**Choice:** Rendered preview from the same in-memory string as the editor via block parsing + SwiftUI `AttributedString(markdown:)` for inline runs, plus a clickable wiki-link list extracted from `[[...]]` patterns.

**Why:** Avoid embedding a browser for the default path. No WebKit dependency.

## Decision: three note view modes (v0.5)

**Choice:** One detail surface at a time — **Source** (raw `MarkdownTextView`), **Live Preview** (hybrid: render blocks, click to edit block source), **Reading** (full-width preview). Mode is persisted (`lyra.noteViewMode`); **⌘E** cycles modes.

**Why:** Matches common vault workflows without side-by-side split complexity. Live Preview stays hybrid (not full WYSIWYG) so disk Markdown remains the single source of truth with simple range splice on commit.

**Consequence:** Block parse attaches UTF-16 source ranges (`MarkdownPreviewBlocks.parseRanged`) for splice-safe edits.

## Decision: sandbox + security-scoped bookmarks

**Choice:** App sandbox enabled; user selects the vault folder; bookmark data stored to reopen the last vault.

**Why:** Mac App Store–friendly defaults while still allowing full access to the chosen tree.

## Decision: wiki link resolution

**Syntax:** `[[Note Name]]` or `[[Note Name.md]]`.

**Rule:** Case-insensitive match on the file stem within the vault; first match wins if duplicates exist. Unresolved links are styled differently and do not navigate in v0.1.

## Concurrency

- UI and stores: `@MainActor`
- File I/O: async helpers so large scans do not freeze the UI
- Autosave: ~500ms debounce; also save on note switch and app background/terminate

## Non-goals (architecture)

Plugin hosts, CRDT sync, Electron shells, multi-window document architecture beyond a simple primary window, background full-text indexing.
