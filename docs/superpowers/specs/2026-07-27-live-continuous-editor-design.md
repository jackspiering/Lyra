# Live mode: continuous editor (drop hybrid block edit)

**Date:** 2026-07-27  
**Status:** Approved for implementation  
**Supersedes (partial):** §4 “Live Preview — hybrid blocks” in `2026-07-27-lyra-v0.5-view-modes-design.md`

## 1. Problem

Live mode today is a hybrid block editor: the note renders as idle blocks; clicking a block opens a raw Markdown field with **Done** / **Cancel**. That feels modal and unlike Obsidian-style live editing. Users want a blinking caret wherever they click and every keystroke to update the note immediately—no per-block selection chrome and no commit/discard buttons.

## 2. Decision

**Live uses the same continuous `MarkdownTextView` as Source** for the full note string.

| Mode | Surface | Editable |
|------|---------|----------|
| Source | `MarkdownTextView` (syntax-highlighted Markdown) | Yes |
| Live | Same continuous `MarkdownTextView` | Yes |
| Reading | Rendered blocks (`MarkdownPreviewView`) | No |

Source and Live are **intentionally identical** for this change. Differentiating Live later (e.g. richer inline rendering) is out of scope. Reading remains the rendered, non-editable surface (images, wiki list).

## 3. Behavior

- Click anywhere in Live → system blinking caret (standard `NSTextView` focus/selection).
- Typing updates `editor.text` and triggers the existing autosave path via `onEdit` / `noteEdited()`; no separate draft or commit step.
- No per-block tap-to-edit, no Done, no Cancel, no frozen block list.
- **⌘E** still cycles Source → Live → Reading; mode still persists (`lyra.noteViewMode`).
- Image paste in Live uses the same path as Source (`LyraTextView` + `AttachmentStore`).
- Wiki link click-to-open from **idle Live blocks** goes away with hybrid UI; navigation remains available from **Reading** (and any future Live enhancement).

## 4. Implementation

### 4.1 UI wiring

In `ContentView.noteDetail`, `case .livePreview` uses the same `MarkdownTextView` binding and callbacks as `case .source` (text, vault root, `onEdit`, paste error). Prefer duplicating the small switch arm or a private helper over a heavy abstraction.

### 4.2 Remove hybrid Live machinery

| Remove | Why |
|--------|-----|
| `LivePreviewView` hybrid UI (focus index, draft, splice, Done/Cancel) | No longer used |
| `liveCommitToken` and all increments / `commitToken` plumbing | Only forced hybrid block commit before mode/note switch, save, background |
| Mode-switch “commit Live edit first” special cases that only exist for hybrid | Continuous editor has no pending draft |

Delete `Lyra/Preview/LivePreviewView.swift` if nothing Live-specific remains. Keep `MarkdownPreviewBlocks` / `parseRanged` / splice helpers if tests or Reading still need them; do not delete pure range helpers solely because Live no longer calls them unless they become dead.

### 4.3 Docs

Update user-facing and architecture copy that describes Live as “click a block → Done”:

- `README.md`
- `CONTRIBUTING.md`
- `docs/architecture.md` (three-mode section: Live = continuous editor, not hybrid block edit)
- `AGENTS.md` only if it still claims hybrid Live behavior

## 5. Out of scope

- True Obsidian-style inline WYSIWYG (rendered look while typing in one document)
- Visual differentiation of Source vs Live
- Changing Reading behavior or Source highlighter
- New dependencies or WebKit

## 6. Testing

### Manual

1. Live: click in the note → blinking caret; type → text updates; no Done/Cancel UI.
2. Autosave / ⌘S persist edits made in Live.
3. ⌘E cycles Source → Live → Reading; both Source and Live remain editable.
4. Image paste (⌘V) in Live still writes `_attachments/` and inserts `![](...)`.
5. Reading still renders images and wiki links; not editable.

### Automated

No new pure-logic unit tests required if Live only reuses `MarkdownTextView`. Leave existing parse/range tests intact if those helpers remain.

## 7. Files (expected)

| Path | Change |
|------|--------|
| `Lyra/App/ContentView.swift` | Live → `MarkdownTextView`; drop `liveCommitToken` |
| `Lyra/Preview/LivePreviewView.swift` | Delete |
| Xcode project / target membership | Drop deleted file if listed |
| `README.md`, `CONTRIBUTING.md`, `docs/architecture.md` | Live description |

## 8. Success criteria

- Live has no Done/Cancel and no block selection edit mode.
- Live has a normal blinking text caret on click and continuous typing.
- Source and Live both edit the same note string; Reading stays rendered read-only.
- Docs match the new behavior.
