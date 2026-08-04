# Lyra

<p align="center">
  <img src="Assets/lyra-logo.png" alt="Lyra" width="128" height="128">
</p>

<p align="center">
  <strong>Native macOS editor for local Markdown vaults.</strong><br>
  Point it at a folder of <code>.md</code> files. Edit, link, preview, export PDF.
  Files stay on disk as plain text. No Electron. No cloud account.
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square">
  <img alt="Version" src="https://img.shields.io/badge/version-0.8.0-informational?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

## Download

[Latest DMG](https://github.com/jackspiering/Lyra/releases) (ad-hoc signed for App Sandbox, **not notarized**).

macOS may still warn on first open. Use **System Settings → Privacy & Security → Open Anyway**, or build from source below. (Control-click → Open is no longer a reliable bypass on macOS 15+.)

## Quick start

1. Open Lyra → Open Vault… (⌘O)
2. Pick a folder of Markdown notes
3. Select a note in the sidebar
4. Switch Source / Reading with the control or ⌘E

| Shortcut | Action |
|----------|--------|
| ⌘O | Open vault |
| ⌘N | New note |
| ⌘S | Save now |
| ⌘E | Toggle Source ↔ Reading |
| ⌘R | Refresh vault from disk |

Autosave runs after about 500ms of idle time. The toolbar shows **Unsaved**, **Save failed**, or **Autosave paused** when relevant.

If the file changes on disk while you have unsaved edits, Lyra asks whether to keep your buffer or reload from disk. **Cancel** pauses autosave so the dialog does not loop; press ⌘S when you are ready to resolve. Quit is blocked while a save is refused (conflict, missing file, or I/O error).

If the open note is moved or deleted outside Lyra, you get a **Note moved or deleted** dialog — save a copy at the old path, or close the note. Lyra will not silently recreate a deleted file on every keystroke.

### View modes

| Mode | Behavior |
|------|----------|
| Source | Raw Markdown with syntax highlighting |
| Reading | Full-width preview (task checkboxes, clickable `[[wiki]]` links) |

## Features

| Feature | Description |
|---------|-------------|
| Local vault | Folder of UTF-8 `.md` files; disk is the source of truth |
| Sidebar | Nested folders and notes; skips `.git` and hidden files |
| Refresh | File → Refresh Vault (⌘R), or when the window becomes active |
| Multiple vaults | One vault per window (File → New Window / Open Vault opens another) |
| Settings | Lyra → Settings: appearance (System / Light / Dark) and About |
| Context export | Right-click note → Export PDF; folder → separate or single PDF |
| Wiki links | `[[Note Name]]` resolves inside the vault |
| Paste images | ⌘V writes under `_attachments/` and inserts a note-relative `![](...)` (Source; local images only) |
| Export PDF | File → Export PDF… for the open note (multi-page; inline bold/italic) |
| Typography | [Inter](https://rsms.me/inter/) (SIL OFL) for UI and notes; mono for code |
| Errors | Plain-language alerts for permissions, missing files, disk full, and similar failures |

Out of scope: plugins, graph view, cloud sync, tag indexes, iOS, full WYSIWYG.

## Who it's for

You keep notes as plain Markdown and want a Mac UI that does not invent a proprietary store. Files remain git-friendly on disk. No account.

## Build from source

Requires macOS 15+, Xcode 16+ (Swift 5.10+).

```bash
git clone https://github.com/jackspiering/Lyra.git
cd Lyra
open Lyra.xcodeproj
```

Scheme Lyra → destination My Mac → Run.

```bash
bash Scripts/smoke.sh        # layout checks (Linux or Mac)
bash Scripts/xcode-test.sh   # build + unit tests (Mac only)
```

<details>
<summary>Ship a release DMG</summary>

Marketing version in Xcode must match the tag (`0.8.0` ↔ `v0.8.0`):

```bash
git tag v0.8.0 && git push origin v0.8.0
```

CI builds an **ad-hoc signed** `Lyra-0.8.0.dmg` (sandbox entitlements applied; not Developer ID / notarized) and uploads it to [Releases](https://github.com/jackspiering/Lyra/releases).

```bash
VERSION=0.8.0 bash Scripts/package-dmg.sh   # local Mac → build/dist/
```

More: [docs/ci.md](docs/ci.md)

</details>

## Project layout

| Path | Role |
|------|------|
| `Lyra/App/` | Window shell, themes, fonts, errors, view modes |
| `Lyra/Vault/` | Tree scan, CRUD, bookmarks, attachments, wiki resolve |
| `Lyra/Editor/` | TextKit source editor, highlight, autosave |
| `Lyra/Preview/` | Reading, PDF export |
| `Lyra/Models/` | Shared types |
| `LyraTests/` | Unit tests for pure logic |
| `docs/` | Architecture, CI, design specs |

## Docs

| Doc | Audience |
|-----|----------|
| [docs/architecture.md](docs/architecture.md) | Design decisions and invariants |
| [docs/ci.md](docs/ci.md) | CI, tests, DMG releases |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Dev setup and manual checklist |
| [AGENTS.md](AGENTS.md) | Rules for AI agents and humans |
| [docs/superpowers/](docs/superpowers/) | Versioned design specs |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Prefer small PRs. Update this README when user-facing behavior changes.

## Acknowledgments

- [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font License 1.1 (`Lyra/Resources/Fonts/Inter-OFL.txt`)

## License

[MIT](LICENSE) © 2026 Jack Spiering
