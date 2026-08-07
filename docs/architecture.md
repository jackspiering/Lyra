# Architecture

Lyra is a single macOS app target with module-shaped folders. This doc is the decision log that keeps the product small and local-first.

## Invariants

1. **Disk is source of truth** — vault = directory tree; notes = UTF-8 `.md` files. No sidecar database.
2. **macOS only** — no iOS or multiplatform abstractions “just in case.”
3. **Native UI** — SwiftUI + AppKit. No Electron. No WebKit for the default path.
4. **Sandbox-friendly** — security-scoped bookmarks for user-selected vault folders.
5. **YAGNI** — no plugins, graph, sync, tag index, or theme marketplace unless explicitly requested.

## Layout

| Folder | Responsibility |
|--------|----------------|
| `App/` | Shell, navigation, open vault, theme, fonts, errors, `NoteViewMode`, window command routing |
| `Vault/` | Scan, CRUD, bookmarks, wiki resolve, `_attachments` paste storage |
| `Editor/` | `NSTextView` source editing, highlight, autosave |
| `Preview/` | Block parse, Reading, PDF export |
| `Models/` | Shared types (`VaultNode`) |

One primary type per file when practical.

## Decisions

### Plain files on disk

**Choice:** Notes are normal Markdown files in a folder the user picks.

**Why:** Zero lock-in; trivial git/backup; agents and tools can read the vault without an API.

**Consequence:** Refresh the tree from disk after mutations. No separate index DB.

### Single app target, folder modules

**Choice:** One Xcode app target; code grouped by role (not SPM packages yet).

**Why:** Real Mac app (sandbox, menus, TextKit) with clear boundaries without package ceremony.

### TextKit source editor

**Choice:** AppKit `NSTextView` via `NSViewRepresentable` + light regex highlight.

**Why:** Native feel and control; better long-term path than a WebView editor.

### Native preview (no WebKit)

**Choice:** Block parser + SwiftUI / `AttributedString` for inline Markdown; wiki links listed for navigation.

**Why:** Avoid embedding a browser for the default experience.

### Two note view modes (v0.5+)

**Choice:** One detail surface: **Source** | **Reading**. Persisted as `lyra.noteViewMode`; **⌘E** toggles. (An earlier no-op “Live” mode was removed.)

**Why:** Source is continuous `MarkdownTextView` (caret on click, live typing). Reading is rendered, non-editable preview (images, wiki links). A third identical editor mode was not worth the UI weight.

### Multi-window vaults (v0.7+)

**Choice:** `WindowGroup` — one vault (`VaultStore`) per window.

**Why:** Users need two folders open at once without a multi-vault tab bar. Menu commands target the key window only; quit flushes every open editor via `AppSession`.

**Consequence:** Opening a vault while one is already open creates a new window for the chosen folder.

### In-window note tabs (v0.9+)

**Choice:** Custom tab bar inside each vault window (`NoteTabController` + one `EditorViewModel` per tab). Shared sidebar for the window’s vault. No `NSWindow` native tabbing (that would duplicate whole windows and reintroduce per-tab “No Vault Open”); automatic window tabbing is disabled so the system title-bar `+` does not appear.

**Why:** Open several notes without losing the vault tree; empty tabs can create a note, focus search, or close without dropping the vault.

**Consequence:** Quit and window teardown register/unregister every tab editor with `AppSession`. Last tab close leaves one empty tab (vault stays open). From 0.9.1, selecting a note from the sidebar opens a new tab when the active tab already has a different note (reuses if already open); File → Open in New Tab is explicit.

### Window chrome decomposition (v0.9.3)

**Choice:** `ContentView` was split so the window shell, dialogs/sheets, command routing, and AppKit bridge helpers live in separate files (`ContentViewChrome`, `ContentViewCommands`, `WindowStateReaders`, `NewNoteNameField`) instead of one 1000+ line file.

**Why:** The monolith had outgrown “one primary type per file”; the split keeps the module map honest without changing behavior.

**Consequence:** The old `VaultStore.ValidatedRename` type moved into `FilenameValidation.Result` so `App/` no longer depends on a `Vault/` type. File-menu commands are still routed via notifications gated by the key window (`ContentViewCommands`); a `@FocusedValue`-based rewrite is the deferred follow-up.

### Inter typeface (v0.5)

**Choice:** Bundle Inter (SIL OFL) for UI, editor, and preview. Code fences use system monospaced.

**Why:** Readable open-source screen font; registered at launch with `CTFontManagerRegisterFontsForURL`.

### Plain-language errors (v0.5)

**Choice:** `UserFacingError` maps Cocoa/POSIX failures to short titles and actionable tips before alerts.

**Why:** Domain codes and raw `localizedDescription` are hard to act on.

### Wiki links

**Syntax:** `[[Note Name]]` or `[[Note Name.md]]`.

**Rule:** Case-insensitive stem match in the vault; first match wins. Unresolved links do not navigate.

### Concurrency

- UI / stores: `@MainActor`
- Vault tree scan: `Task.detached` from `VaultStore.refresh` so large trees do not block the first frame
- Autosave: ~500ms debounce; also save on note switch, background, and quit
- External edits: file metadata plus content identity is captured at open/save; a coordinated dirty write against a changed file prompts Keep Mine / Reload
- Vault mutations reject symlinked paths and keep scanned notes and attachments inside the selected vault root
- PDF export: rendering and folder file I/O run in a detached task; UI panels and error state return to the main actor

## Attachments

**Choice:** Clipboard image paste writes under `{vaultRoot}/_attachments/` and inserts a relative `![](…)` path at the caret (`AttachmentStore`).

**Why:** Plain files next to notes; other Markdown tools can open the vault without Lyra.

## PDF export

**Choice:** Export the open note via PDFKit / native layout (`NotePDFExporter`), not pandoc or WebKit print.

## Non-goals

Plugin hosts, CRDT sync, Electron, NSDocument multi-window architecture, background full-text indexing, full WYSIWYG round-trip.
