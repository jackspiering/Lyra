# Lyra

<p align="center">
  <img src="Assets/lyra-logo.png" alt="Lyra" width="128" height="128">
</p>

<p align="center">
  <strong>Native macOS Markdown vault editor.</strong><br>
  Open a folder of plain <code>.md</code> files. Edit, link, preview. No Electron, no cloud, no lock-in.
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square">
  <img alt="Version" src="https://img.shields.io/badge/version-0.4.0-informational?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

## Download

[Latest release (DMG)](https://github.com/jackspiering/Lyra/releases) — unsigned. First launch: right-click → **Open** if Gatekeeper warns.

## Quick start

1. Launch Lyra → **Open Vault…** (⌘O)
2. Choose a folder of Markdown files
3. Select a note in the sidebar to edit

| Action | Shortcut |
|--------|----------|
| Open vault | ⌘O |
| New note | ⌘N |
| Save | ⌘S |
| Toggle preview | ⌘⇧P |

Autosave after ~500ms idle; ⌘S saves immediately.

## Features

| Feature | Description |
|---------|-------------|
| Local vault | Folder of UTF-8 `.md` files — disk is source of truth |
| Sidebar tree | Folders + notes; ignores `.git` / hidden files |
| Source editor | TextKit + basic Markdown highlighting |
| Live preview | Side-by-side, toggleable; local images render |
| Wiki links | `[[Note Name]]` resolves inside the vault |
| CRUD | Create, rename, delete notes and folders |
| Paste images | ⌘V → `_attachments/` + `![](...)` insert |
| Export PDF | **File → Export PDF…** for the current note |
| Native UI | SwiftUI + AppKit; custom app icon |

**Not in scope:** plugins, graph view, cloud sync, tags index, iOS.

## Why

Plain Markdown on disk (git-friendly, no proprietary store) with a native Mac UI — not an Electron shell. For people who want a local vault without a plugin host or cloud account.

## Build from source

**Requires:** macOS 15+, Xcode 16+ (Swift 5.10+)

```bash
open Lyra.xcodeproj
```

Scheme **Lyra** → **My Mac** → Run (⌘R).

```bash
bash Scripts/smoke.sh        # structure checks (any OS)
bash Scripts/xcode-test.sh   # build + unit tests (Mac + Xcode)
```

CI details: [docs/ci.md](docs/ci.md).

<details>
<summary>Release DMG</summary>

Tag must match the Xcode marketing version (`0.4.0` ↔ `v0.4.0`):

```bash
git tag v0.4.0 && git push origin v0.4.0
```

CI attaches unsigned `Lyra-0.4.0.dmg` to the [Release](https://github.com/jackspiering/Lyra/releases).

```bash
VERSION=0.4.0 bash Scripts/package-dmg.sh   # local Mac only → build/dist/
```

</details>

## Docs

| Doc | For |
|-----|-----|
| [docs/architecture.md](docs/architecture.md) | Layout, invariants, design decisions |
| [AGENTS.md](AGENTS.md) | AI agents extending the codebase |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setup, tests, PR checklist |
| [docs/superpowers/](docs/superpowers/) | Design specs and plans |

## License

[MIT](LICENSE) © 2026 Jack Spiering
