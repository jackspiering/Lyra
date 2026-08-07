<p align="center">
  <img src="Assets/lyra-logo.png" alt="Lyra logo" width="128" height="128">
</p>

<h1 align="center">Lyra</h1>

<p align="center">
  <strong>A native macOS editor for local Markdown vaults.</strong><br>
  Edit plain files, follow wiki links, preview notes, and export PDFs.
</p>

<p align="center">
  <a href="https://github.com/jackspiering/Lyra/actions/workflows/ci.yml">
    <img alt="CI" src="https://github.com/jackspiering/Lyra/actions/workflows/ci.yml/badge.svg">
  </a>
  <img alt="macOS 15 or later" src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square">
  <img alt="Swift 5.10" src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square">
  <img alt="Version 0.9.3" src="https://img.shields.io/badge/version-0.9.3-informational?style=flat-square">
  <a href="LICENSE">
    <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
  </a>
</p>

Lyra is for people who want a focused writing environment without giving up ownership of their files. A vault is a folder on your Mac. Notes remain UTF-8 Markdown files that work with Git, Finder, scripts, and other editors.

## Why Lyra

- **File-first:** No database, proprietary format, cloud account, or lock-in.
- **Native:** SwiftUI and AppKit provide a Mac app with a real menu bar, windows, TextKit editing, and sandbox support.
- **Focused:** Source and Reading modes keep writing and review in one workspace.
- **Durable:** Autosave, external-edit detection, missing-file recovery, and guarded window closing protect in-memory work.
- **Portable:** Wiki links, relative images, attachments, and PDF export work with ordinary Markdown conventions.

## Download

Download the latest [Lyra release](https://github.com/jackspiering/Lyra/releases/tag/v0.9.3), then drag Lyra to Applications.

The release DMG is ad-hoc signed for App Sandbox and is not notarized. If macOS blocks the first launch, open **System Settings > Privacy & Security > Open Anyway**. You can also [build Lyra from source](#build-from-source).

## Features

- **Source mode:** TextKit editing with Markdown syntax highlighting, undo, autosave, and standard text editing behavior.
- **Reading mode:** Native Markdown block rendering with headings, lists, quotes, code, images, and clickable wiki links.
- **Note tabs:** Open multiple notes inside one vault window without losing the sidebar.
- **Multiple vaults:** Open separate vault folders in separate windows.
- **Vault search:** Filter the sidebar by note name or path. Search is local and does not build a full-text index.
- **Wiki links:** Resolve `[[Note Name]]` and `[[Note Name.md]]` links inside the current vault.
- **Image paste:** Paste an image with Command-V to store it under `_attachments/` and insert a relative Markdown image link.
- **PDF export:** Export one note, a folder of notes, or a combined folder document.
- **Recovery controls:** Review external changes, recreate a moved note when requested, and prevent failed saves from closing a window.
- **Preferences:** Configure appearance, new-note naming, and Trash confirmations.

## Quick Start

1. Open Lyra and choose **Open Vault**.
2. Select a folder containing Markdown notes.
3. Select a note in the sidebar.
4. Edit in **Source** mode or review in **Reading** mode.
5. Use **File > Export PDF** when you need a printable copy.

### Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| Command-O | Go to File, or Open Vault when no vault is open |
| Command-N | Create a note |
| Shift-Command-N | Open a new vault window |
| Command-T | Open a new note tab |
| Shift-Command-W | Close the current note tab |
| Command-E | Toggle Source and Reading modes |
| Command-S | Save the current note |
| Command-R | Refresh the vault from disk |
| Command-F | Focus vault search |
| Command-Delete | Move the selected item to Trash |

Autosave runs after approximately 500 milliseconds of inactivity. If a note changes outside Lyra, the editor presents Keep Mine and Reload Theirs options. Dirty windows stay open until their buffers save or you explicitly choose a recovery action.

## Vault Format

Lyra reads a directory tree and includes visible `.md` files. The vault itself stays transparent:

```text
My Vault/
|-- Welcome.md
|-- Projects/
|   `-- Roadmap.md
`-- _attachments/
    `-- pasted-image-20260807-120000.png
```

Lyra does not create a sidecar database or proprietary note format. Hidden files, package directories, and symlinked entries are ignored by the vault tree. Clipboard images are stored in `_attachments/` and referenced with relative paths.

## Build From Source

Requirements:

- macOS 15 or later
- Xcode 16 or later
- Swift 5.10 or later

Clone the repository and open the Xcode project:

```bash
git clone https://github.com/jackspiering/Lyra.git
cd Lyra
open Lyra.xcodeproj
```

Select the **Lyra** scheme, choose **My Mac**, and run.

### Verification

The repository provides checks for both Linux and macOS environments:

```bash
# Structure, documentation, version, entitlement, whitespace, and shell checks
bash Scripts/smoke.sh

# Build and unit tests, requires macOS and Xcode
bash Scripts/xcode-test.sh
```

Release packaging details are documented in [docs/ci.md](docs/ci.md).

## Project Structure

| Path | Responsibility |
| --- | --- |
| `Lyra/App/` | Window shell, navigation, tabs, settings, menus, theme, and errors |
| `Lyra/Vault/` | Vault scanning, file operations, bookmarks, attachments, search, and wiki resolution |
| `Lyra/Editor/` | TextKit editing, highlighting, autosave, and paste handling |
| `Lyra/Preview/` | Reading mode, Markdown blocks, image resolution, and PDF export |
| `Lyra/Models/` | Shared value types such as `VaultNode` |
| `LyraTests/` | Unit tests for pure logic and editor durability |
| `docs/` | Architecture decisions and CI documentation |

## Documentation

- [Architecture](docs/architecture.md): Product invariants and technical decisions.
- [CI and releases](docs/ci.md): Continuous integration, signing, and DMG packaging.
- [Contributing](CONTRIBUTING.md): Development setup and pull request expectations.
- [Agent guidance](AGENTS.md): Repository rules for coding agents and humans.

## Scope

Lyra intentionally stays small and local. Plugins, graph views, cloud sync, accounts, tag indexes, iOS support, and full WYSIWYG round-tripping are outside the current scope.

## Contributing

Issues and pull requests are welcome. Before opening a pull request:

1. Read [CONTRIBUTING.md](CONTRIBUTING.md).
2. Keep changes focused and update tests for pure logic.
3. Run `bash Scripts/smoke.sh`.
4. Update documentation when user-facing behavior changes.

## Acknowledgments

Lyra bundles [Inter](https://rsms.me/inter/) by Rasmus Andersson under the SIL Open Font License 1.1. The license text is included at `Lyra/Resources/Fonts/Inter-OFL.txt`.

## License

Lyra is available under the [MIT License](LICENSE). Copyright 2026 Jack Spiering.
