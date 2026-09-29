# AGENTS.md

The rules for changing Lyra. They apply to agents and humans alike. The reasons behind
the design live in [`docs/architecture.md`](docs/architecture.md).

## What Lyra is

A native macOS notes app over a folder of Markdown. Writing comes first; wiki links,
backlinks, and search exist so people can leave Obsidian without Electron. A note is a
UTF-8 `.md` file, and its **filename** is its identity. The first `#` heading is just
content.

## Commands

| What | Command | Runs on |
| --- | --- | --- |
| Whitespace, shell, and project checks | `bash Scripts/smoke.sh` | Any OS |
| Build and unit tests | `bash Scripts/xcode-test.sh` | macOS + Xcode 26 |
| Same, plus window snapshots | `TEST_RUNNER_LYRA_SNAPSHOTS=1 bash Scripts/xcode-test.sh` | macOS + Xcode 26 |
| Release DMG | `bash Scripts/package-dmg.sh` | macOS + Xcode 26 |

**No Mac?** There is no Swift toolchain for this app on Linux, so the
**Build & test (macOS)** CI job is your compiler. Push, then read its log (errors also
appear as PR annotations). Its `lyra-snapshots` artifact shows the window, sidebar,
palettes, and backlinks in Night and Parchment. Liquid Glass renders blank offscreen.
Write Swift that type-checks the first time:

- Annotate closure and collection types in large literals instead of leaning on inference.
- Warnings are errors. Under Xcode 26 that includes isolation: no `@MainActor` static as a
  default argument, no main-actor call from a nonisolated closure.

## Rules

1. **Disk is the source of truth.** No database or persisted index. In-memory maps rebuilt
   on scan are fine.
2. **macOS only**, SwiftUI + AppKit. No iOS targets, no Electron, no WebKit in the default path.
3. **Sandboxed.** Vault access goes through security-scoped bookmarks.
4. **Plain text in the editor.** Source styles Markdown but never hides or rewrites it.
   Reading is read-only. No WYSIWYG.
5. **Stay small.** Out of scope unless the maintainer asks: plugins, graph view, sync,
   accounts, tag index, daily notes, frontmatter UI, `![[embeds]]`, `[[Note#heading]]`,
   a theme picker, and UI test suites. The offscreen snapshot test is not a UI test suite.
6. **No dependencies.** Apple frameworks only.
7. **No personal email in git.** Commit as
   `46534141+jackspiering@users.noreply.github.com` (set it locally).

## Code map

```
Lyra/
  App/       Window shell, tabs, sidebar, palettes, inspector, settings, theme, fonts, errors
  Vault/     Scan, file operations, bookmarks, wiki links and backlinks, search, attachments
  Editor/    NSTextView source editor, highlighter, autosave, paste
  Preview/   Reading blocks, images, PDF export
  Models/    Shared value types
LyraTests/   XCTest unit tests
Assets/      Icon source (lyra-icon.svg)
Scripts/     smoke, xcode-test, package-dmg
docs/        Architecture decisions, CI, design mockups
```

- **Register every new Swift file in `Lyra.xcodeproj/project.pbxproj`** (file reference,
  group, and build phase). The project does not use synchronized folders, so an
  unregistered file silently won't compile. Extend an existing file when the addition is small.
- One primary type per file when practical.
- `App/` may depend on `Vault/`; `Vault/` must not depend on `App/` views.

## Conventions

- Follow the Swift API Design Guidelines and existing names (`VaultStore`,
  `FileSystemVault`, `WikiLinkResolver`, `EditorViewModel`, `UserFacingError`).
- UI state is `@MainActor` + `@Observable`. Keep file I/O on large trees off the main thread.
- User-visible failures go through `UserFacingError` and `VaultStore.present…`.
- Take colors from `LyraTheme` and type from `LyraFonts`, never hard-coded values.
  `LyraTheme` has the Night and Parchment tokens (`paper`, `chrome`, `sidebar`, `raised`,
  `scrim`, `fill`, `hairline`, `ink`, `markup`, `accent`, `onAccent`) and the writing
  column shared by title, Source, and Reading. `LyraFonts` has the bundled Inter sizes
  (`prose`, `label`, `caption`, `title`, `headingSize(level:)`).
- No system gray backgrounds (`.bar`, `windowBackgroundColor`) in the vault window. On
  macOS 26, don't paint opaque fills over Liquid Glass; gate them with
  `#available(macOS 26, *)` as `SidebarView` does. Mockups are in `docs/design/`.
- The app icon is drawn in `Assets/lyra-icon.svg`. Re-render the AppIcon PNGs from it
  when it changes, with thicker strokes at 16 and 32 px.

## Tests

Add XCTest cases in `LyraTests/` for pure logic: paths and wiki resolution, aliases,
backlinks, naming, ranges, highlighter attributes, error copy. Extend an existing test
file when one fits (new files need pbxproj entries too). Views are checked by hand on a
Mac and in the snapshots. Say in the PR what you could not check.

## Shipping a change

1. Keep it focused. Use small commits prefixed `feat:`, `fix:`, `docs:`, `test:`, `ci:`, or `chore:`.
2. Update `README.md` for anything a user can see, and `docs/architecture.md` when a
   structure or decision changes.
3. Bump the version when the change ships in the app. Skip docs, tests, CI, and tooling.
   Use PATCH for fixes, MINOR for new features or settings, and MAJOR for breaking changes
   (MINOR before 1.0). A bump sets `MARKETING_VERSION` in all four configurations of
   `project.pbxproj` and raises `CURRENT_PROJECT_VERSION` by one. If `main` bumped first,
   merge it and bump from there. **Merging a bump to `main` publishes the release.**
4. Run `bash Scripts/smoke.sh`, plus `bash Scripts/xcode-test.sh` on a Mac.
5. Fill in the PR template: what and why, how you verified it, the version, and what
   still needs a manual look.

When in doubt, choose fewer files, fewer abstractions, and less configuration.
