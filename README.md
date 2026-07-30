# Lyra

<p align="center">
  <img src="Assets/lyra-logo.png" alt="Lyra" width="128" height="128">
</p>

<p align="center">
  <strong>A native macOS editor for local Markdown vaults.</strong><br>
  Open any folder of <code>.md</code> files. Edit, link, preview, export. No Electron, no cloud, no lock-in.
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square">
  <img alt="Version" src="https://img.shields.io/badge/version-0.5.0-informational?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
  <a href="https://coderabbit.ai"><img alt="CodeRabbit Pull Request Reviews" src="https://img.shields.io/coderabbit/prs/github/jackspiering/Lyra?utm_source=oss&utm_medium=github&utm_campaign=jackspiering%2FLyra&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews&style=flat-square"></a>
</p>

## Download

[**Latest DMG**](https://github.com/jackspiering/Lyra/releases) — unsigned builds.

First open: right-click the app → **Open** if Gatekeeper blocks it.

## Quick start

1. Open Lyra → **Open Vault…** (⌘O)
2. Pick a folder of Markdown notes
3. Select a note in the sidebar
4. Switch **Source · Live · Reading** (or **⌘E**)

| Shortcut | Action |
|----------|--------|
| ⌘O | Open vault |
| ⌘N | New note |
| ⌘S | Save now |
| ⌘E | Cycle Source → Live → Reading |

Autosave runs after ~500ms idle.

### View modes

| Mode | Behavior |
|------|----------|
| **Source** | Raw Markdown with syntax highlighting |
| **Live** | Continuous Markdown editor (same as Source); click for caret, type to edit |
| **Reading** | Full-width preview only |

## Features

| Feature | Description |
|---------|-------------|
| Local vault | Any folder of UTF-8 `.md` files — disk is the source of truth |
| Sidebar | Nested folders and notes; skips `.git` and hidden files |
| Wiki links | `[[Note Name]]` resolves inside the vault |
| Paste images | ⌘V → `_attachments/` + `![](...)` (Source or Live) |
| Export PDF | **File → Export PDF…** for the open note |
| Typography | [Inter](https://rsms.me/inter/) (SIL OFL) for UI and notes; mono for code |
| Errors | Plain-language alerts (permissions, missing files, disk full, …) |

**Not in scope:** plugins, graph view, cloud sync, tag indexes, iOS, full WYSIWYG.

## Who it's for

People who want a **local** Markdown vault with a real Mac UI — git-friendly plain files, no account, no proprietary store. Closer to a focused native editor than a plugin platform.

## Build from source

**Requires:** macOS 15+, Xcode 16+ (Swift 5.10+)

```bash
git clone https://github.com/jackspiering/Lyra.git
cd Lyra
open Lyra.xcodeproj
```

Scheme **Lyra** → destination **My Mac** → Run (⌘R).

```bash
bash Scripts/smoke.sh        # layout checks (Linux or Mac)
bash Scripts/xcode-test.sh   # build + unit tests (Mac only)
```

<details>
<summary>Ship a release DMG</summary>

Marketing version in Xcode must match the tag (`0.5.0` ↔ `v0.5.0`):

```bash
git tag v0.5.0 && git push origin v0.5.0
```

CI uploads unsigned `Lyra-0.5.0.dmg` to [Releases](https://github.com/jackspiering/Lyra/releases).

```bash
VERSION=0.5.0 bash Scripts/package-dmg.sh   # local Mac → build/dist/
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

See [CONTRIBUTING.md](CONTRIBUTING.md). Small PRs; update the README when user-facing behavior changes.

## Acknowledgments

- [Inter](https://rsms.me/inter/) by Rasmus Andersson — SIL Open Font License 1.1 (`Lyra/Resources/Fonts/Inter-OFL.txt`)

## License

[MIT](LICENSE) © 2026 Jack Spiering
