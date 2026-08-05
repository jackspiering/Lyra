# Lyra

<p align="center">
  <img src="Assets/lyra-logo.png" alt="Lyra" width="128" height="128">
</p>

<p align="center">
  <strong>Native macOS editor for local Markdown vaults.</strong><br>
  Point it at a folder of <code>.md</code> files. Edit, link, preview, export PDF.<br>
  Files stay on disk as plain text. No Electron. No cloud account.
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square">
  <img alt="Version" src="https://img.shields.io/badge/version-0.9.2-informational?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

## Download

[Latest DMG](https://github.com/jackspiering/Lyra/releases) — ad-hoc signed for App Sandbox, **not notarized**.

On first open, macOS may block it. Use **System Settings → Privacy & Security → Open Anyway**, or build from source.

## Quick start

1. Open Lyra → **Open Vault…** (or File → Open Vault…)
2. Pick a folder of Markdown notes
3. Select a note in the sidebar
4. Toggle **Source** / **Reading** with the control or **⌘E**

| Shortcut | Action |
|----------|--------|
| ⌘O | Go to File… (or Open Vault… if none open) |
| ⌘N | New note |
| ⌘T | New empty tab |
| ⌘E | Toggle Source ↔ Reading |
| ⌘S | Save now |
| ⌘R | Refresh vault from disk |
| ⌘F | Focus vault search |
| ⌘⌫ | Move selection to Trash |

Autosave runs after ~500ms idle. Unsaved state shows on the window close button. If the file changes on disk while you have edits, Lyra asks whether to keep your buffer or reload.

## Features

| Feature | Description |
|---------|-------------|
| Local vault | Folder of UTF-8 `.md` files; disk is the source of truth |
| Source / Reading | Syntax-highlighted editor, or full-width preview with images and `[[wiki]]` links |
| Note tabs | Multiple notes share one vault sidebar (⌘T, empty-tab actions) |
| Multiple vaults | One vault per window |
| Wiki links | `[[Note Name]]` resolves inside the vault |
| Paste images | ⌘V saves under `_attachments/` and inserts a relative image link |
| Vault search | Filter the tree by name or path (⌘F; not full-text) |
| Export PDF | File → Export PDF… for the open note |
| Settings | Appearance, new-note naming, Trash confirmations, About |

**Out of scope:** plugins, graph view, cloud sync, tag indexes, iOS, full WYSIWYG.

## Who it's for

You keep notes as plain Markdown and want a Mac UI that does not invent a proprietary store. Files stay git-friendly on disk. No account.

## Build from source

Requires **macOS 15+** and **Xcode 16+** (Swift 5.10+).

```bash
git clone https://github.com/jackspiering/Lyra.git
cd Lyra
open Lyra.xcodeproj
```

Scheme **Lyra** → destination **My Mac** → Run.

```bash
bash Scripts/smoke.sh        # layout checks (Linux or Mac)
bash Scripts/xcode-test.sh   # build + unit tests (Mac only)
```

<details>
<summary>Ship a release DMG</summary>

Marketing version in Xcode must match the tag (`0.9.2` ↔ `v0.9.2`):

```bash
git tag v0.9.2 && git push origin v0.9.2
```

CI builds an ad-hoc signed `Lyra-0.9.2.dmg` and uploads it to [Releases](https://github.com/jackspiering/Lyra/releases).

```bash
VERSION=0.9.2 bash Scripts/package-dmg.sh   # local Mac → build/dist/
```

Details: [docs/ci.md](docs/ci.md)

</details>

## Project layout

| Path | Role |
|------|------|
| `Lyra/App/` | Window shell, tabs, settings, theme, fonts, errors |
| `Lyra/Vault/` | Tree scan, CRUD, bookmarks, attachments, wiki resolve |
| `Lyra/Editor/` | TextKit source editor, highlight, autosave |
| `Lyra/Preview/` | Reading mode, PDF export |
| `Lyra/Models/` | Shared types |
| `LyraTests/` | Unit tests |
| `docs/` | Architecture and CI |

## Docs

| Doc | Audience |
|-----|----------|
| [docs/architecture.md](docs/architecture.md) | Design decisions and invariants |
| [docs/ci.md](docs/ci.md) | CI, tests, DMG releases |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Dev setup and PR checklist |
| [AGENTS.md](AGENTS.md) | Rules for AI agents and humans |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Prefer small PRs. Update this README when user-facing behavior changes.

## Acknowledgments

Also listed in Settings → About:

- [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font License 1.1 (`Lyra/Resources/Fonts/Inter-OFL.txt`)

## License

[MIT](LICENSE) © 2026 Jack Spiering
