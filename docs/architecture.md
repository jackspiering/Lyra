# Architecture

Why Lyra is built the way it is. The rules that follow from this are in
[AGENTS.md](../AGENTS.md).

## Product

A native Mac notes app over a folder of Markdown. Writing comes first; wiki links,
backlinks, and in-memory search exist so a person can leave Obsidian. A full Obsidian
clone (graph, plugins, sync) would break the rules; a writing-only app would fight the
vault features.

**Limits.** In-memory maps are sized for hundreds of notes, not tens of thousands. Scans
stop at 64 directory levels. Note bodies over 2 MB, and notes that can't be read as UTF-8,
stay openable and resolve as link targets but are left out of search, aliases, and
backlinks. PDF export stops at 2,000 pages.

## Files and identity

- **Plain files.** Notes are the visible `.md` files in a folder the user picks. There is
  no index database; the tree is rescanned from disk after every change. Other files may
  sit in the vault, but they are not notes.
- **The filename is the note.** The title, tab, and sidebar show the file stem, and editing
  the title renames the file. A leading `#` heading is just content. Git and Finder
  already use the path, and two identities would confuse.
- **Stay inside the vault.** Mutations reject symlinked paths and keep notes and
  attachments under the vault root. Creation is exclusive where practical; reads don't
  follow symlinks and require regular files.

## App structure

- One Xcode app target with folders by role, not Swift packages: a real Mac app (sandbox,
  menus, TextKit) without package ceremony.
- `ContentView` is the window shell and wiring. Dialogs and sheets live in
  `ContentViewChrome`, AppKit bridges in `WindowStateReaders`, wiki navigation in
  `WikiFlow`, and PDF export in `PDFExportFlow`. Both flows share one editor-error helper,
  so presentation cannot fork.
- Each vault window publishes a scene-scoped `VaultCommands` (`focusedSceneValue`), so
  only the key window answers menu commands. A quit-time save failure is an app-wide
  notification, because the failing editor may be in a background window.

## Windows and tabs

- **One vault per window** (`WindowGroup`, one `VaultStore` each). Opening a vault while
  one is open makes a new window, bound to the pick by a UUID handoff. Each window keeps
  its security-scoped bookmark in `@SceneStorage` and reopens it after a relaunch; a
  window without one reopens the last vault, once per launch. A stale bookmark does not
  auto-open: the first window asks before binding to the resolved folder.
- **Tabs are Lyra's own** (`NoteTabController`, one `EditorViewModel` per tab), not
  `NSWindow` tabbing, which would duplicate whole windows. Automatic window tabbing is
  off. No pins and no tab history. A sidebar click opens a new tab when the active tab
  holds a different note, or switches to the note's open tab. Closing the last tab leaves
  an empty tab, and the vault stays open.
- Each editor keeps its `NSTextView` alive, so undo, caret, and scroll survive tab
  switches and ⌘E.
- `AppSession` tracks every editor and flushes them at quit. If a closed window's note
  still fails to save, Lyra asks before discarding it.

## Source and Reading

- **One surface, two modes**, persisted as `lyra.noteViewMode` and toggled with ⌘E.
  Editable Reading (WYSIWYG) was considered and rejected: a native round-trip editor is a
  different product.
- **Source** is an `NSTextView` with a regex highlighter (`MarkdownHighlighter`). It
  sizes headings by level, draws markers (`#`, `**`, `_`, backticks, `[[ ]]`, link URLs)
  in the quiet `markup` color, uses a monospaced face for code, and never hides
  characters. Only the edited paragraph is restyled. Command-click follows a wiki link.
- **Reading** is a block parser plus SwiftUI and `AttributedString`, no WebKit. It
  supports ATX and Setext headings, fenced code, bullet, ordered, and task lists with
  continuation lines, blockquotes, thematic breaks, inline code, emphasis, links, images,
  and wiki links. It does not support indented code blocks, complex nesting, embeds, or
  heading fragments. A leading YAML block renders as code, in Reading and in PDF.
- **Reading links.** `http`, `https`, and `mailto` open in the system handler. `file:`
  opens only a plain, non-executable file inside the vault. A relative link to a `.md`
  file in the vault opens as a note. Every other scheme is ignored, so a shared vault
  cannot launch apps.
- Images in Reading and PDF are checked through ImageIO metadata against a 50-megapixel,
  16,384 px budget before a bitmap is decoded.

## Look

- **`LyraTheme`** holds one palette with two looks that follow the system: *Night* (navy,
  with the logo's gold) and *Parchment* (warm paper, bronze-gold). Views use its named
  tokens, never system grays. PDF export keeps its own print colors.
- **Writing column.** Title, Source, and Reading share a centered 680 pt column. Source
  gets it from a width-dependent `textContainerInset` with zero line-fragment padding, so
  its text lines up with the SwiftUI title.
- **Type.** Bundled Inter (SIL OFL: Regular, Italic, SemiBold, Bold), registered at launch
  with `CTFontManagerRegisterFontsForURL`. Prose is 16 pt with 7 pt line spacing; code
  uses the system monospaced face. View → Bigger / Smaller magnifies the Source scroll
  view (0.7×–2×) instead of changing font sizes, so the scale and column keep their
  proportions.
- **Surfaces.** Go to File and Search share one Spotlight-style palette (`VaultPalette`) on
  a `raised` surface above a `scrim`. Word count is a floating pill. On macOS 26 the
  sidebar drops its opaque fill so Liquid Glass shows the window's tone; macOS 15 keeps
  the fill. Mockups are in `docs/design/`.
- **Icon.** A flat gold lyre under Vega, Lyra's brightest star, on the Night navy. It is
  drawn in `Assets/lyra-icon.svg`, and the AppIcon PNGs follow the macOS rounded-square
  template.

## Wiki links

Syntax: `[[Note]]`, `[[Note.md]]`, `[[Folder/Note]]`, and `[[path|alias]]`, where the path
is the target and the alias is the display text. No `[[Note#heading]]`.

- Matching is case-insensitive and path-aware: `[[Folder/Note]]` prefers that path, and a
  bare `[[Note]]` matches the stem. A real path or stem beats a YAML alias.
- If more than one note still matches, show a picker with vault-relative paths. Never guess.
- An unresolved link does not navigate. It offers **Create**, and nothing is written until
  the user confirms. Create uses the link's path; a bare name goes in the linking note's
  folder. Links to attachments (`[[image.png]]`) never offer Create.
- Renaming a note offers to update the `[[links]]` that uniquely resolved to it. Open
  notes change in their tab, and closed notes go through the normal save path. Nothing is
  rewritten without confirmation.
- Aliases come only from `aliases:` (a string or a list) in a leading `---` YAML block.
  All other frontmatter is ordinary text.
- `WikiLinkResolver` builds lookup maps once per scan (stem, every path suffix, alias, URL),
  so a resolve is a dictionary lookup. The backlink index resolves every link in the
  vault, so a linear resolve would make each scan quadratic.

## Backlinks

A trailing inspector, hidden until opened from the toolbar or View → Backlinks, lists the
notes that link here with `[[wiki]]` links. Plain Markdown links don't count. There is no
outgoing list, outline, or graph: backlinks are what someone leaving Obsidian looks for,
and a graph is a second product. The index is rebuilt on each scan with open editors'
live text laid over it, and it updates after a short typing pause. Each card shows the
line around the first matching link (`WikiLinkResolver.backlinkContext`), computed when
the card renders and never stored.

## Search and Find

- **⌘F** opens the system find bar on the Source text view.
- **⌘O**, Go to File, ranks names ignoring case: an exact name first, then a name prefix,
  a word in the name, anywhere in the name, every query word in the name, the path, and
  finally the query's letters in order (`VaultSearch.rankNotes`).
- **⇧⌘F** searches note bodies in an in-memory index rebuilt on each scan. Each result shows
  the note, its path, and one snippet, capped at 200 results.
- Both use one palette over the window and rank in a detached task, so typing stays
  smooth. A note opened from the palette, or just created, takes focus in Source; a
  sidebar click leaves focus in the sidebar.
- The sidebar's name and path filter is labeled Filter and is not bound to ⌘F.

## Refresh and saving

- The tree is rescanned on window activation and on ⌘R. There is no FSEvents watcher: a
  watcher adds sandbox surface, and a scan is cheap. At the same moments, an open note
  with no unsaved edits reloads if its file changed, or shows the moved-or-deleted dialog.
- The scan runs detached from `VaultStore.refresh`. It stats every note (size,
  modification date, file number) and reuses the cached body when that stamp is
  unchanged. The stamp is taken before the read, so a write that lands mid-read is caught
  next time. Indexes rebuild only when the tree or a body changed, and observed properties
  are assigned only when their value changes, so an idle activation redraws nothing.
- Autosave waits about 500 ms after typing stops. It also saves on note switch,
  backgrounding, and quit. A conflict the user cancelled stays deferred while backgrounded;
  ⌘S, closing the window, and quit still surface it.
- File metadata and content identity are captured at open and save. A dirty write over a
  changed file prompts Keep Mine / Reload. Saves go through `NSFileCoordinator`, open and
  reload read the bytes once, and existing notes are replaced with
  `FileManager.replaceItemAt`, which keeps creation date, permissions, and Finder tags.

## Attachments

Pasted images go to `{vault}/_attachments/` (hidden from the sidebar), and a relative
`![](…)` link goes in at the caret (`AttachmentStore`). Names are
`pasted-image-yyyyMMdd-HHmmss.png`, with a numeric suffix on a case-insensitive collision.
A copied image file keeps its bytes and extension. A clipboard picture is stored only when
no text type is listed before it, because Office, Numbers, and Pages put a picture of
copied text after the text. PDF is never pasted as an image.

## PDF export

Export the open note with native layout (`NotePDFExporter`), not pandoc or WebKit.
Rendering and file I/O run detached. Output stops at 2,000 pages with a truncation line.
There is no folder export, which would be a second product.

## Errors

`UserFacingError` maps Cocoa and POSIX failures to a short title and an actionable tip.
Absolute paths in fallback copy are cut to their last component so screenshots don't leak
directory structure.

## Toolchain and release

- Lyra is built with Xcode 26 and the macOS 26 SDK, which gives it Liquid Glass, and it
  deploys to macOS 15. It stays in Swift 5 language mode; the Swift 6 migration is deferred.
- `WindowSnapshotTests` renders the real views over a sample vault in Night and Parchment,
  offscreen, when `LYRA_SNAPSHOTS=1`, and CI uploads the PNGs, so contributors without a
  Mac can see UI changes. Offscreen rendering cannot draw system materials, so Liquid
  Glass comes out blank; check it by hand.
- Releases are ad-hoc signed DMGs with a published SHA-256, not notarized until there is a
  Developer ID. See [ci.md](ci.md).
