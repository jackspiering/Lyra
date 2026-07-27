# Lyra

<p align="center">
  <img src="Assets/lyra-logo.png" alt="Lyra" width="160" height="160">
</p>

**Lyra** is a native, lightweight, local-first Markdown editor and knowledge vault for macOS.  
It is an open-source alternative focused purely on editing and navigating local Markdown files — no Electron, no cloud sync, no proprietary formats.

Inspired by the simplicity of tools like Obsidian for local vaults, but built as a proper native **SwiftUI** macOS app.

**Goals:** speed, native feel, pure Markdown on disk, a solid editing experience, and an AI-agent-friendly codebase from day one.

## Name origin

The name **Lyra** comes from the constellation Lyra and the mythical lyre of Orpheus — the instrument associated with poetry, knowledge, harmony, and the music of the spheres. It reflects a tool for organizing and composing personal knowledge with elegance and clarity.

## Features (v0.4)

- Open a local folder as a **vault**
- Sidebar with a recursive tree of folders and `.md` files
- Markdown **source editor** with basic syntax highlighting
- **Live preview** (side-by-side, toggleable)
- Wiki-style links: `[[Note Name]]` (resolve within the vault)
- Create, rename, and delete notes and folders
- Paste images into notes (saved under `_attachments/`)
- Live preview renders local images
- **Export PDF…** for the current note
- **Autosave** (debounced) and **⌘S** to save immediately
- Native macOS UI (SwiftUI + AppKit where it helps)
- Custom **macOS app icon** (Dock / Finder / About)
- Unsigned **DMG** builds on version tags via GitHub Actions
- All data stays as plain `.md` files — no database, no lock-in

## Download

Grab the latest DMG from [Releases](https://github.com/jackspiering/Lyra/releases).

Builds are **unsigned** (not notarized). First launch: right-click → **Open** if Gatekeeper warns.

## Screenshots

_Screenshots coming soon._ Place images under `docs/screenshots/` and link them here.

## Requirements

- macOS 15 Sequoia or later
- Xcode 16+ (Swift 5.10+) to build from source

## Quick start

1. Launch Lyra → **Open Vault…**
2. Choose a folder of Markdown files
3. Select a note in the sidebar to edit

## Build & run

```bash
open Lyra.xcodeproj
```

In Xcode: select the **Lyra** scheme, destination **My Mac**, then **Run** (⌘R).

From the command line:

```bash
bash Scripts/smoke.sh                 # structure checks (any OS)
bash Scripts/xcode-test.sh            # build + unit tests (Mac + Xcode)
```

CI runs both on PRs (see [docs/ci.md](docs/ci.md)).

### Release DMG (macOS runner)

Push a version tag after merge (example for **0.4.0**):

```bash
git tag v0.4.0
git push origin v0.4.0
```

GitHub Actions builds an **unsigned** `Lyra-0.4.0.dmg` and attaches it to a [GitHub Release](https://github.com/jackspiering/Lyra/releases). Details: [docs/ci.md](docs/ci.md).

Local (Mac only):

```bash
VERSION=0.4.0 bash Scripts/package-dmg.sh   # → build/dist/Lyra-0.4.0.dmg
```

## Architecture overview

Single macOS app target with module-shaped folders:

| Folder | Role |
|--------|------|
| `Lyra/App/` | Window shell, navigation, open-vault UI |
| `Lyra/Vault/` | Filesystem vault, tree scan, CRUD, wiki resolution |
| `Lyra/Editor/` | Source editor, highlighting, autosave |
| `Lyra/Preview/` | Live Markdown preview |
| `Lyra/Models/` | Lightweight shared types |

**Invariants:** disk is the source of truth; no Electron; no cloud; no proprietary format.

Details: [docs/architecture.md](docs/architecture.md)  
Design (v0.1 baseline): [docs/superpowers/specs/2026-07-27-lyra-v0.1-design.md](docs/superpowers/specs/2026-07-27-lyra-v0.1-design.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). AI agents should read [AGENTS.md](AGENTS.md) first.

## License

[MIT](LICENSE) © 2026 Jack Spiering
