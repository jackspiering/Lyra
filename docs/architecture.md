# Architecture

Lyra is a single macOS app target with module-shaped folders. This doc is the decision log that keeps the product local-first.

## Product (v0.11)

**Choice:** Native Mac PKM over a folder of Markdown. Writing is first. Wiki links, backlinks, and in-memory full-text search exist so a person can leave Obsidian. The app is public and small.

**Why:** The old “focused writer only” sentence fought the vault features. A full Obsidian clone (graph, plugins, sync) fights the invariants. Writing-first PKM is the middle that matches the user.

**Honesty limit:** In-memory maps are for hundreds of notes, not tens of thousands. Lyra does not owe a disk index. Scan walks at most 64 directory levels. Note bodies larger than 2 MB stay openable but are left out of search, aliases, and backlinks. Notes that cannot be read or decoded as UTF-8 are also left out of those indexes. PDF export stops at 2,000 pages.

## Invariants

1. **Disk is source of truth** — vault = directory tree; notes = UTF-8 `.md` files. No sidecar database. In-memory maps rebuilt on scan are allowed.
2. **macOS only** — no iOS or multiplatform abstractions “just in case.”
3. **Native UI** — SwiftUI + AppKit. No Electron. No WebKit for the default path.
4. **Sandbox-friendly** — security-scoped bookmarks for user-selected vault folders.
5. **YAGNI** — no plugins, graph view, sync, tag index, theme marketplace, daily notes, frontmatter UI, embeds, heading fragments, or WYSIWYG unless explicitly requested.

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

**Choice:** Notes are normal Markdown files in a folder the user picks. Only visible `.md` files are notes.

**Why:** Zero lock-in; trivial git/backup; agents and tools can read the vault without an API.

**Consequence:** Refresh the tree from disk after mutations. No separate index DB. Go to File only lists `.md` files. Other text files may sit on disk. Lyra does not treat them as notes.

### Note identity is the filename

**Choice:** The filename stem is the note’s name. The title bar and tab label show that stem. Editing the title renames the file. A leading `#` heading is content only.

**Why:** Disk is source of truth. Git and Finder already use the path. Two identities (H1 vs file) confuse a PKM.

### Single app target, folder modules

**Choice:** One Xcode app target; code grouped by role (not SPM packages yet).

**Why:** Real Mac app (sandbox, menus, TextKit) with clear boundaries without package ceremony.

### TextKit source editor

**Choice:** AppKit `NSTextView` via `NSViewRepresentable` + light regex highlight.

**Why:** Native feel and control; better long-term path than a WebView editor.

### Native preview (no WebKit)

**Choice:** Block parser + SwiftUI / `AttributedString` for inline Markdown; wiki links listed for navigation.

**Why:** Avoid embedding a browser for the default experience.

**Supported subset:** ATX and Setext headings, fenced code blocks, bullet/ordered/task lists with continuation lines, blockquotes, thematic breaks, inline code/emphasis/links/images, and wiki links. Four-space-indented code blocks, complex nested Markdown, embeds, and heading fragments remain outside the supported Reading subset.

### Two note view modes (v0.5+)

**Choice:** One detail surface: **Source** | **Reading**. Persisted as `lyra.noteViewMode`; **⌘E** toggles. (An earlier no-op “Live” mode was removed. Editable Reading / WYSIWYG was considered again and rejected.)

**Why:** Source is continuous `MarkdownTextView` (caret on click, live typing). Reading is rendered, non-editable preview (images, wiki links). Native WYSIWYG round-trip is a different editor.

### Multi-window vaults (v0.7+)

**Choice:** `WindowGroup` — one vault (`VaultStore`) per window.

**Why:** Users need two folders open at once without a multi-vault tab bar. Menu commands target the key window only; quit flushes every open editor via `AppSession`.

**Consequence:** Opening a vault while one is already open creates a new window for the chosen folder. That window is bound to the pick with a UUID handoff so a later Open Vault cannot consume the earlier folder.

### In-window note tabs (v0.9+)

**Choice:** Custom tab bar inside each vault window (`NoteTabController` + one `EditorViewModel` per tab). Shared sidebar for the window’s vault. No `NSWindow` native tabbing (that would duplicate whole windows and reintroduce per-tab “No Vault Open”); automatic window tabbing is disabled so the system title-bar `+` does not appear. Do not grow tabs (no pins, no tab history).

**Why:** Open several notes without losing the vault tree; empty tabs can create a note, focus search, or close without dropping the vault.

**Consequence:** Quit and window teardown register/unregister every tab editor with `AppSession`. Last tab close leaves one empty tab (vault stays open). From 0.9.1, selecting a note from the sidebar opens a new tab when the active tab already has a different note (reuses if already open); File → Open in New Tab is explicit.

### Window chrome decomposition (v0.9.3)

**Choice:** `ContentView` was split so the window shell, dialogs/sheets, command routing, and AppKit bridge helpers live in separate files (`ContentViewChrome`, `VaultCommands`, `WindowStateReaders`, `NewNoteNameField`) instead of one 1000+ line file.

**Why:** The monolith had outgrown “one primary type per file”; the split keeps the module map honest without changing behavior.

**Consequence:** The old `VaultStore.ValidatedRename` type moved into `FilenameValidation.Result` so `App/` no longer depends on a `Vault/` type. File-menu commands were originally routed via notifications gated by the key window; from 0.10.2 each vault window publishes a scene-scoped `VaultCommands` value (`focusedSceneValue`) and the menu buttons call it directly, so only the key vault window answers. Quit-save failure remains an app-global notification observed by every window because the failing editor may belong to a background window.

From 0.10.2 the decomposition continued along the same seams: wiki-link
resolution, the pick-or-create sheet, and shared tab activation live in
`WikiFlow`; PDF export orchestration lives in `PDFExportFlow`. `ContentView`
is shell + wiring, and both flows share one canonical editor-error surfacing
helper so presentation policy cannot fork.

### Inter typeface (v0.5)

**Choice:** Bundle Inter (SIL OFL) for UI, editor, and preview. Code fences use system monospaced. Appearance is System / Light / Dark only. No theme marketplace.

**Why:** Readable open-source screen font; registered at launch with `CTFontManagerRegisterFontsForURL`.

### Visual system (v0.11)

**Choice:** One palette in `LyraTheme` with two looks that follow the system appearance. *Night* (dark) uses navy surfaces with the logo gold as accent. *Parchment* (light) uses warm paper with a deeper bronze-gold. Surfaces, ink, markup, and accent are named tokens; views do not use system gray backgrounds (`.bar`, `windowBackgroundColor`) in the vault window. Title, Source, and Reading share one centered writing column (`LyraTheme.columnWidth`, 680pt). Source sets it through a width-dependent `textContainerInset` with zero line-fragment padding, so the text lines up with the SwiftUI title. Prose is Inter 16pt with 7pt line spacing. The word-count status bar became a floating pill. Mockups live in `docs/design/`.

**Why:** Lyra looked like a stock SwiftUI sample. The brand only showed up in syntax colors, and full-width 14pt text made long lines. A single column and a calmer page make writing, the first job, feel better. It uses no new dependencies and adds no theme picker.

**Consequence:** Source styling is still plain text. `MarkdownHighlighter` sizes headings by level, draws syntax markers (`#`, `**`, `_`, backticks, `[[ ]]`, link URLs) in the quiet `markup` color, uses a monospaced face for code, and adds paragraph spacing. It never hides characters, so this is not WYSIWYG. Only the attributes of the edited paragraph are restyled, as before. PDF export keeps its own print colors.

### Plain-language errors (v0.5)

**Choice:** `UserFacingError` maps Cocoa/POSIX failures to short titles and actionable tips before alerts. Fallback Cocoa copy has POSIX absolute paths reduced to the last path component.

**Why:** Domain codes and raw `localizedDescription` are hard to act on. Absolute paths in alerts leak directory structure in screenshots.

### Wiki links

**Syntax:** `[[Note Name]]`, `[[Note Name.md]]`, or `[[Folder/Note]]`. Optional display alias: `[[path|alias]]` (path is the target, alias is display). No `[[Note#heading]]`.

**Agreed rules:**

- Match is case-insensitive.
- Resolve is path-aware. `[[Folder/Note]]` prefers that path. Bare `[[Note]]` matches the stem.
- If more than one note still matches, do not guess. Show a picker with vault-relative paths.
- A real path or stem beats a YAML alias. If still tied, show the picker.
- Unresolved links do not navigate. Offer **Create**. Do not create the file until the user confirms.
- Create uses the path when the link has one. A bare name creates a `.md` file in the same folder as the linking note. Then open the new note with the existing tab rules.
- Command-click a wiki link in Source to follow it. The same resolve rules apply.

**YAML:** Parse only a leading `---` block for `aliases:` (string or list). Those names resolve as extra stems. All other frontmatter is ordinary text.

Reading click and Source Command-click use the same rules. Preview still rewrites `[[path|alias]]` to a `lyra-wiki:` link for display.

### Backlinks

**Choice:** A trailing inspector lists notes that link here through `[[wiki]]` only. Ordinary Markdown file links do not count. No outgoing list, no outline, no graph canvas.

**Why:** Backlinks are what a person leaving Obsidian looks for. A graph view is a second product.

**Consequence:** The pane is hidden until the user opens it (toolbar or View → Backlinks). It is available in Source and in Reading. The backlink index is rebuilt on each vault scan. Open editors overlay their live text onto that index. From 0.11 each card also shows the line around the first link that resolves here (`WikiLinkResolver.backlinkContext`). It is computed from the in-memory bodies when the inspector renders and is not stored.

### Search and Find

**Choice:**

- **⌘F** — system find bar on the Source `NSTextView`.
- **⇧⌘F** — vault full-text search. In-memory index, rebuilt on each vault scan. Results show note, path, and one snippet. This is a lightweight palette, not a third workspace.
- The sidebar name/path filter stays. It is not Find.

**Why:** A writer expects ⌘F to search this note. Body search is how they leave Obsidian without a disk index.

The sidebar name filter is labeled Filter. It is not bound to ⌘F.

### Refresh

**Choice:** Rescan the tree on window activation and on **⌘R**. Rebuild wiki, backlinks, and the in-memory search map from that scan. No FSEvents watcher unless a human asks after this hurts.

**Why:** Hundreds of notes can pay for a full scan. A watcher is extra sandbox surface.

### Concurrency

- UI / stores: `@MainActor`
- Vault tree scan: `Task.detached` from `VaultStore.refresh` so large trees do not block the first frame
- Autosave: ~500ms debounce; also save on note switch, background, and quit
- External edits: file metadata plus content identity is captured at open/save; a coordinated dirty write against a changed file prompts Keep Mine / Reload. Editor saves always go through `NSFileCoordinator` so a file that appears between the missing-file check and the write cannot be clobbered silently. Open/reload and post-write snapshots use one coherent byte read so the buffer and conflict identity cannot describe different disk versions
- Vault mutations reject symlinked paths and keep scanned notes and attachments inside the selected vault root. Note and attachment creation uses exclusive file creation where practical; reads avoid following symlinks and require regular files
- PDF export: rendering and file I/O run in a detached task; UI panels and error state return to the main actor. Export stops at 2,000 pages and writes a truncation line in the PDF
- Reading and PDF image decode use ImageIO metadata and a 50-megapixel / 16,384-px budget before materializing a bitmap
- A stale security-scoped bookmark does not auto-open or re-persist. The first window asks before binding to the resolved folder

## Attachments

**Choice:** Clipboard image paste writes under `{vaultRoot}/_attachments/` and inserts a relative `![](…)` path at the caret (`AttachmentStore`). Hide `_attachments` from the sidebar tree. Generated names are timestamp-based (`pasted-image-yyyyMMdd-HHmmss.png`) with a numeric suffix on collision. Occupancy checks are case-insensitive; Unicode-normalization aliases are not treated as a practical risk for same-second generated names.

**Why:** Plain files next to notes; other Markdown tools can open the vault without Lyra.

## PDF export

**Choice:** Export the **open note** via native layout (`NotePDFExporter`), not pandoc or WebKit print.

**Why:** Printable copy of the note you are writing. Folder batch export is a second product.

Folder batch export is not offered. The exporter can still stitch notes in tests.

## Release

**Choice:** macOS 15+. Ad-hoc signed DMG. Not notarized. README must say how to open a blocked app. Each release publishes a SHA-256 of the DMG.

**Why:** Public and small. Developer ID and notarization stay a later human step (`docs/ci.md`). The checksum lets a download be checked against the GitHub release until notarization exists.

## Non-goals

Plugin hosts, CRDT or cloud sync, accounts, Electron, NSDocument multi-window architecture, persisted or background full-text index, full WYSIWYG round-trip, graph view, tag index, theme marketplace, daily notes, frontmatter property UI, `![[embeds]]`, `[[Note#heading]]`, iOS.
