# Continuous Live Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Live mode a continuous full-document `MarkdownTextView` (same as Source)—blinking caret on click, every keystroke updates the note, no Done/Cancel or per-block edit chrome.

**Architecture:** Drop hybrid block Live Preview. Wire `case .livePreview` to the same `MarkdownTextView` path as Source. Delete `LivePreviewView` and all `liveCommitToken` plumbing that only forced block commits. Keep Reading as rendered read-only. Keep `MarkdownPreviewBlocks.parseRanged` / `replacing` for Reading-related tests and any future use.

**Tech Stack:** SwiftUI + AppKit `NSTextView` (`MarkdownTextView` / `LyraTextView`). No new dependencies. macOS only.

**Spec:** `docs/superpowers/specs/2026-07-27-live-continuous-editor-design.md`

## Global Constraints

- Disk is source of truth; UTF-8 `.md` only; no sidecar DB
- macOS only; no iOS / Electron / WebKit for this feature
- YAGNI: do not implement Obsidian-style inline WYSIWYG; Source and Live may be identical
- Always update `README.md` for user-visible behavior
- Update `Scripts/smoke.sh` when removing required paths / pbx names
- Git author: `jackspiering` / `46534141+jackspiering@users.noreply.github.com` only (noreply)
- Prefer smallest diff; no drive-by refactors

## File map

| Path | Role |
|------|------|
| `Lyra/App/ContentView.swift` | Live → `MarkdownTextView`; remove `liveCommitToken` and async-only-for-commit delays where safe |
| `Lyra/Preview/LivePreviewView.swift` | Delete |
| `Lyra.xcodeproj/project.pbxproj` | Remove LivePreviewView file ref / build file / group / sources entries |
| `Scripts/smoke.sh` | Drop LivePreviewView required path and pbx name |
| `README.md` | Live mode + paste row copy |
| `CONTRIBUTING.md` | Manual smoke steps for Live |
| `docs/architecture.md` | Three-mode section: continuous Live, not hybrid |
| `AGENTS.md` | Module map line for Preview (drop “Live Preview” as hybrid home) |

Keep (do not delete): `MarkdownPreviewBlocks` range helpers + tests, `MarkdownBlockRow`, `MarkdownPreviewView`, `NoteViewMode`.

---

### Task 1: ContentView — continuous Live + drop commit token

**Files:**
- Modify: `Lyra/App/ContentView.swift`

**Interfaces:**
- Consumes: `MarkdownTextView(text:vaultRoot:onEdit:onPasteError:)` (existing)
- Produces: `case .livePreview` and `case .source` both show continuous editable Markdown; no `liveCommitToken`

- [ ] **Step 1: Remove `liveCommitToken` state and every `liveCommitToken += 1`**

Delete:

```swift
@State private var liveCommitToken = 0
```

Remove every line that only increments it (scenePhase, delete dialog, save, open vault, cycle mode, rename, selection change, wiki link, export PDF). Leave the surrounding logic (save, open, etc.) intact.

- [ ] **Step 2: Wire Live to `MarkdownTextView`**

Replace the `.livePreview` arm so it matches Source:

```swift
switch noteViewMode {
case .source, .livePreview:
    MarkdownTextView(
        text: $editor.text,
        vaultRoot: store.rootURL,
        onEdit: { editor.noteEdited() },
        onPasteError: { store.present(context: .pasteImage, message: $0) }
    )
case .reading:
    MarkdownPreviewView(
        text: editor.text,
        noteDirectory: editor.fileURL?.deletingLastPathComponent(),
        vaultRoot: store.rootURL,
        onWikiLink: { openWikiLink($0) }
    )
}
```

Using a combined `case .source, .livePreview` is preferred (one editor surface, no drift).

- [ ] **Step 3: Simplify save / open paths that only delayed for hybrid commit**

**Save notification** — replace token + deferred save with immediate save:

```swift
.onReceive(NotificationCenter.default.publisher(for: .lyraSaveNote)) { _ in
    _ = editor.saveIfNeeded()
    flushEditorError()
}
```

**Selection change** — open the note without waiting a frame for Live commit:

```swift
private func handleSelectionChange(_ newValue: VaultNode.ID?) {
    guard let newValue,
          let root = store.rootNode,
          let node = FileSystemVault.findNode(id: newValue, in: root),
          !node.isDirectory else {
        if store.selectedFileURL() == nil { editor.close() }
        return
    }
    if editor.fileURL?.path != node.url.path {
        editor.open(url: node.url)
        flushEditorError()
    }
}
```

**Wiki link** — drop token; keep save-then-open:

```swift
private func openWikiLink(_ text: String) {
    guard let url = store.resolveWikiLink(text) else { return }
    _ = editor.saveIfNeeded()
    flushEditorError()
    store.selection = url.path
    editor.open(url: url)
    flushEditorError()
}
```

**Export PDF** — drop token; keep save-then-export. You may keep `DispatchQueue.main.async` only if needed for panel presentation; it is no longer required for Live commit. Minimal form:

```swift
private func exportPDF() {
    guard let noteURL = editor.fileURL, let vault = store.rootURL else { return }
    _ = editor.saveIfNeeded()
    flushEditorError()
    do {
        let data = try NotePDFExporter.pdfData(
            markdown: editor.text,
            noteDirectory: noteURL.deletingLastPathComponent(),
            vaultRoot: vault
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = noteURL.deletingPathExtension().lastPathComponent + ".pdf"
        panel.directoryURL = noteURL.deletingLastPathComponent()
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                store.present(error: error, context: .exportPDF)
            }
        }
    } catch {
        store.present(error: error, context: .exportPDF)
    }
}
```

**Rename / delete / open vault / scenePhase / cycle mode:** only remove `liveCommitToken += 1`; keep existing save/close/open behavior.

Confirm with search: no remaining `liveCommitToken` or `LivePreviewView` references in `ContentView.swift`.

- [ ] **Step 4: Commit**

```bash
git add Lyra/App/ContentView.swift
git commit -m "$(cat <<'EOF'
fix(live): use continuous MarkdownTextView; drop commit token

Live matches Source: full-document caret and live typing, no hybrid
block Done/Cancel path.
EOF
)"
```

---

### Task 2: Delete `LivePreviewView` and project/smoke references

**Files:**
- Delete: `Lyra/Preview/LivePreviewView.swift`
- Modify: `Lyra.xcodeproj/project.pbxproj`
- Modify: `Scripts/smoke.sh`

**Interfaces:**
- Consumes: ContentView no longer references `LivePreviewView` (Task 1)
- Produces: app target builds without `LivePreviewView.swift`

- [ ] **Step 1: Delete the source file**

```bash
git rm Lyra/Preview/LivePreviewView.swift
```

- [ ] **Step 2: Remove all four pbxproj entries for LivePreviewView**

In `Lyra.xcodeproj/project.pbxproj`, delete these lines (IDs as of current tree):

1. PBXBuildFile:
   `A10000000000000000000023 /* LivePreviewView.swift in Sources */ = ...`
2. PBXFileReference:
   `B10000000000000000000023 /* LivePreviewView.swift */ = ...`
3. Preview group children entry:
   `B10000000000000000000023 /* LivePreviewView.swift */,`
4. Lyra target Sources:
   `A10000000000000000000023 /* LivePreviewView.swift in Sources */,`

Verify no remaining `LivePreviewView` string in the pbxproj:

```bash
grep -n LivePreviewView Lyra.xcodeproj/project.pbxproj || echo "clean"
```

Expected: `clean` (no matches).

- [ ] **Step 3: Update `Scripts/smoke.sh`**

1. Remove from required paths list:

```bash
  Lyra/Preview/LivePreviewView.swift \
```

2. In the pbxproj name loop, remove `LivePreviewView` from the space-separated list so it becomes:

```bash
for name in LyraApp ContentView VaultStore WikiLinkResolver MarkdownTextView VaultFolderPicker LyraTheme MarkdownPreviewBlocks MarkdownImagePath AttachmentStore AttachmentStoreTests MarkdownImagePathTests NotePDFExporter NotePDFExporterTests NoteViewMode MarkdownBlockRow UserFacingError LyraFonts UserFacingErrorTests; do
```

Optionally add `LivePreviewView.swift` to the “removed / unwanted paths” loop so a reintroduction fails smoke:

```bash
for path in Lyra/App/OpenVaultView.swift Lyra/Models/NoteDocument.swift Lyra/Editor/EditorView.swift Lyra/Preview/LivePreviewView.swift; do
```

- [ ] **Step 4: Run smoke script**

```bash
bash Scripts/smoke.sh
```

Expected: exit 0; no FAIL lines; no requirement for `LivePreviewView`.

- [ ] **Step 5: Commit**

```bash
git add Lyra/Preview/LivePreviewView.swift Lyra.xcodeproj/project.pbxproj Scripts/smoke.sh
git commit -m "$(cat <<'EOF'
chore: remove hybrid LivePreviewView and smoke/pbx references

Live is continuous MarkdownTextView; hybrid block UI is gone.
EOF
)"
```

---

### Task 3: Docs — Live is continuous editor

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `docs/architecture.md`
- Modify: `AGENTS.md` (module map only)

**Interfaces:**
- Produces: user-facing and architecture copy match continuous Live (no Done/Cancel / block click)

- [ ] **Step 1: Update README view modes and paste row**

In the view modes table, set Live to continuous editor:

```markdown
| Mode | Behavior |
|------|----------|
| **Source** | Raw Markdown with syntax highlighting |
| **Live** | Continuous Markdown editor (same as Source); click for caret, type to edit |
| **Reading** | Full-width preview only |
```

In Features, change paste images row:

```markdown
| Paste images | ⌘V → `_attachments/` + `![](...)` (Source or Live) |
```

Search README for `Done` / `block` Live wording and fix any leftover hybrid claims.

- [ ] **Step 2: Update CONTRIBUTING manual smoke**

Replace hybrid Live steps:

```markdown
5. **Live:** click in the note — blinking caret; type — content updates; no Done/Cancel
7. `[[Other Note]]` opens from Reading when the file exists
9. **Live:** paste image (same as Source) → `_attachments/` + link; shows in Reading
```

Adjust numbering if steps 7/9 are the only lines that change; keep the rest of the smoke list.

- [ ] **Step 3: Update architecture three-mode section**

Replace the hybrid Live paragraph in `docs/architecture.md`:

```markdown
### Three note view modes (v0.5+)

**Choice:** One detail surface: **Source** | **Live** | **Reading**. Persisted as `lyra.noteViewMode`; **⌘E** cycles.

**Why:** Matches vault workflows without a permanent side-by-side split. Source and Live both use continuous `MarkdownTextView` over the full note string (caret on click, live typing). Reading is rendered, non-editable preview (images, wiki links).
```

- [ ] **Step 4: Tighten AGENTS module map**

```text
  Preview/    # Block parse, Reading, PDF export
```

(Live no longer lives under a hybrid Preview view.)

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md docs/architecture.md AGENTS.md
git commit -m "$(cat <<'EOF'
docs: describe Live as continuous editor

Align README, CONTRIBUTING, architecture, and AGENTS with the
Source-equivalent Live mode (no hybrid Done/Cancel).
EOF
)"
```

---

### Task 4: Verify (Linux smoke + Mac notes)

**Files:** none (verification only)

- [ ] **Step 1: Smoke**

```bash
bash Scripts/smoke.sh
```

Expected: PASS / exit 0.

- [ ] **Step 2: Grep for dead hybrid UI**

```bash
grep -RIn 'LivePreviewView\|liveCommitToken\|Button("Done")\|Button("Cancel")' \
  Lyra/ README.md CONTRIBUTING.md docs/architecture.md Scripts/ || true
```

Expected: no app-source hits for `LivePreviewView` or `liveCommitToken`. Historical specs under `docs/superpowers/specs/` may still mention hybrid Live — that is OK (superseded by the continuous-editor design doc). `Button("Cancel")` may remain on rename/delete sheets only.

- [ ] **Step 3: Unit tests on Mac (if available)**

```bash
bash Scripts/xcode-test.sh
# or
xcodebuild -scheme Lyra -destination 'platform=macOS' test
```

Expected: all tests pass. On Linux-only agents, skip and note in the handoff.

- [ ] **Step 4: Manual checklist (Mac)**

1. Live: click → blinking caret; type → text updates; no Done/Cancel.
2. Autosave / ⌘S persist Live edits.
3. ⌘E cycles Source → Live → Reading; Source and Live both editable.
4. Image paste in Live writes `_attachments/` and inserts link.
5. Reading still renders; not editable.

- [ ] **Step 5: No further commit unless fixes are needed**

If smoke/tests fail, fix in a follow-up commit on the same branch (`fix/live-continuous-editor`).

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Live continuous `MarkdownTextView` like Source | Task 1 |
| No Done/Cancel / block focus | Task 1 + Task 2 |
| Drop `liveCommitToken` | Task 1 |
| Delete `LivePreviewView` | Task 2 |
| Keep Reading rendered | Task 1 (unchanged arm) |
| Docs README / architecture / CONTRIBUTING | Task 3 |
| Out of scope: WYSIWYG, Source≠Live styling | Not planned |
| Keep parseRanged helpers | Not deleted |
| Manual + smoke verification | Task 4 |

No TBD placeholders. IDs for pbxproj match current tree; re-grep if the project file changes before implementation.
