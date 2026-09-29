# Contributing

Issues and pull requests are welcome. The rules for code, tests, versions, and pull
requests are in [AGENTS.md](AGENTS.md). Despite the name, they apply to humans too.

## Setup

1. Use a Mac with Xcode 26. Lyra itself runs on macOS 15 or later.
2. `git clone https://github.com/jackspiering/Lyra.git && open Lyra/Lyra.xcodeproj`
3. Run the **Lyra** scheme on **My Mac**.

Before opening a pull request, run `bash Scripts/smoke.sh` and `bash Scripts/xcode-test.sh`.
CI runs both.

## Manual check before a release

Unit tests cover the logic. On a Mac with a real vault, these cover the rest:

1. Edit in Source, quit, and relaunch. The text is still there.
2. Press ⌘E for Reading, follow a `[[link]]`, and open the backlinks pane.
3. Create, rename, and delete a note and a folder, including renaming the open note
   mid-sentence. Finder shows exactly one file with all your text.
4. Change the open note on disk, then type. Keep Mine / Reload appears, and ⌘Q never
   drops unsaved edits silently.
5. Find notes with ⌘O and ⇧⌘F, paste an image, and use File → Export PDF.
6. Switch Settings → Appearance between Light and Dark. You get Parchment and Night with
   no gray bands. On macOS 26 the sidebar is Liquid Glass.

## License

Contributions are licensed under the MIT License.
