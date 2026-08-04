# Claude Audit Fixes — Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` (recommended). Tasks are ordered by harm÷effort. Each task ends reviewable and `Scripts/smoke.sh`-green. Do not expand scope beyond the task text.

**Source:** `.orca/drops/lyra-audit.html` (audit of commit `287f12a`, 4 Aug 2026)  
**Branch:** `fix/claude-audit-critical` (from `main`) — **keep one branch / one PR**  
**Goal:** Land critical + high fixes and high-value mediums; open one PR against `main`. Explicitly defer low-ROI items listed at the end.

Also keep a copy of this plan in-repo at `docs/superpowers/plans/2026-08-04-claude-audit-fixes.md` (replace the thinner draft already there when implementing Task A).

---

## Independent review of the audit (do not re-litigate)

I re-read the HTML audit and spot-checked the current tree (WIP on this branch + `main` baseline). Verdict: **trust the critical/high findings; treat medium/low as triage.**

| Cluster | Audit claim | My read | Action |
|--------|-------------|---------|--------|
| **#01 rename trap** | Folder rename leaves editor on dead path; close/save block forever | Confirmed root cause: `refresh()` is async; rename used stale `selectedFileURL()`; close gated on failed save | **Must ship** |
| **#02 New Note never opens** | Eager `selection =` before tree rebuild | Same race as #01 | **Must ship** |
| **#03 unsigned DMG** | `CODE_SIGNING_ALLOWED=NO` drops sandbox | Correct for entitlement embedding; ad-hoc sign is enough for sandbox, **not** Gatekeeper/notarization | **Must ship** (word docs carefully) |
| **#04 wrong version** | Tag vs `MARKETING_VERSION` / hard-coded `CFBundleVersion` | Confirmed drift (`0.5.0` in project while tags at 0.6.x) | **Must ship** |
| **#05 quit discards** | Terminate ignores save result | Confirmed; need `applicationShouldTerminate` cancel | **Must ship** |
| **#06 conflict fail-open** | Missing file / backdated mtime treated as safe | Confirmed; need missing-file path + abs mtime + size | **Must ship** |
| **#07–#08 PDF** | No block split; raw `**` | Confirmed; PDFKit text extraction is the right proof | **Must ship** |
| **#09 highlight EOF** | `NSIntersectionRange` collapses caret at EOF | Confirmed classic AppKit pitfall | **Must ship** |
| **#10 autosave silent** | Autosave drops `Bool` | Confirmed | **Must ship** |
| **#11 ordered lists** | Ordinal + indent stripped | Confirmed in parser | **Must ship** (depth heuristic only — not full CommonMark) |
| **#12 paste URL fetch** | Clipboard URL → `NSImage(contentsOf:)` | Real; sandbox usually blocks network, still wrong | **Must ship** |
| **#13–#14 scan / refresh** | One bad child blanks tree; no rescan | Confirmed | **Must ship** |
| **#15 Cancel conflict** | Cancel only hides dialog | Confirmed | **Must ship** |
| **#26–#27 hollow tests** | PDF byte-length; highlighter string equality | Confirmed | **Must ship** with real assertions |
| **#16 context menu row** | Wrong target on delayed confirm | Plausible UX bug | **Defer** (careful selection design) |
| **#17 DMG every PR** | Release path never in PR CI | True; expensive | **Defer** |
| **#18 Gatekeeper docs** | Control-click Open gone on macOS 15 | True; docs lie today | **Fix in docs task** (not code) |
| **#19 movable release action tag** | `softprops/action-gh-release@v*` | Real supply-chain nit | **Defer** (optional pin if touching workflow) |
| **#20 path `..` guard** | `assert_under_root` string-only | Confirmed | **Must ship** (in package-dmg WIP) |
| **#21–#24 parser polish** | Front matter, regex rebuild, blockquote | Real but parser day-project | **Defer** (except free wins while touching lists) |
| **#22–#23 perf** | Per-line regex / full-string binding | Real, not user-facing broken | **Defer** |
| **#28–#29 more tests** | Autosave debounce / full CRUD suite | Nice | **Defer** beyond what tasks already add |
| **#30 smoke lists** | Hand-maintained path lists | Confirmed noise | **Must ship** lean smoke |
| **#31–#34, #36** | Live ghosts, doc drift, menus, checklist | Mostly true | **Ship menus + checklist + PR template; don’t delete historical plans** |
| **#35 warnings-as-errors** | Zero warnings today | Safe; **do not** bundle Swift 6 / strict concurrency | **Ship** |
| **Strict concurrency / notarization** | Called out as later | Agree | **Out of scope** |

**What the audit got right philosophically:** core save machine is sound; bugs are at seams (stale tree, release packaging, hollow tests). Do not “refactor the editor” or replace the block parser with Foundation Markdown wholesale in this PR.

---

## Global constraints

- macOS only; no new dependencies; disk is source of truth; sandbox-friendly; YAGNI
- User-visible failures → `UserFacingError` + `VaultStore.present…`
- Update `README.md` for user-visible behavior; `docs/ci.md` / `docs/architecture.md` when CI/structure changes
- Git author (local only): `jackspiering` / `46534141+jackspiering@users.noreply.github.com`
- Tests must assert real behavior (attributes, PDFKit text, paths on disk)
- Verify: always `bash Scripts/smoke.sh`; on Mac also `bash Scripts/xcode-test.sh`
- Do **not** enable Swift 6 / `SWIFT_STRICT_CONCURRENCY=complete`
- Do **not** claim ad-hoc signing fixes Gatekeeper/notarization
- Prefer smallest working change; no FSEvents watcher, no plugin system

---

## Current branch reality (read this first)

Branch `fix/claude-audit-critical` already has **~1.1k lines uncommitted** covering most of the code:

| Area | Status on WIP |
|------|----------------|
| Rename return URL + `relocate` + `pendingSelection` + last create parent | **Implemented** |
| Conflict fail-closed, missing file, quit cancel, sticky save fail, toolbar indicators | **Implemented** |
| Highlight EOF + paste span + fileURL-only image paste | **Implemented** |
| Scan `continue` + `isPackageKey` + Refresh ⌘R + scenePhase rescan | **Implemented** |
| package-dmg ad-hoc sign, path normalize, version guards, lean smoke, MARKETING 0.6.2, warnings-as-errors | **Implemented** |
| PDF span/code split, image maxH, inline MD, ordered lists + depth | **Implemented** |
| Menus (New/Open/Refresh/Toggle/Export disabled) | **Implemented** |
| Unit tests for rename/relocate/close/conflict/PDF/highlighter/lists/scan | **Mostly implemented** |
| `README.md` / `CONTRIBUTING.md` / `docs/ci.md` version + Gatekeeper + checklist | **Not done** (still 0.5.0 / right-click Open / Live in PR template) |
| Logical commits | **None yet** — one giant dirty tree |
| Xcode tests | **Not run here** (Linux agent; smoke already passes) |

**Execution posture:** do **not** rewrite the WIP. Treat Tasks 1–7 as *verify / finish residual gaps / commit slices*. Task 8 is docs. Task 9 is residual cleanup + PR.

If a subagent finds a task already complete, it should only: run smoke, fix any real holes, commit that slice, stop.

---

## File map (expected final touch set)

| Path | Role |
|------|------|
| `Lyra/Vault/VaultStore.swift` | pending selection, rename → URL?, create parent memory |
| `Lyra/Vault/FileSystemVault.swift` | per-child scan errors; package skip |
| `Lyra/Editor/EditorViewModel.swift` | relocate, missing file, conflict defer, close escape, quit-safe save |
| `Lyra/Editor/MarkdownHighlighter.swift` | EOF caret clamp |
| `Lyra/Editor/MarkdownTextView.swift` | paste highlight span; file-only image load |
| `Lyra/App/ContentView.swift` | rename relocate, dialogs, notifications, save indicators |
| `Lyra/LyraApp.swift` | AppDelegate terminate, menus, store/editor hoist |
| `Lyra/Preview/MarkdownPreviewBlocks.swift` | list ordinal/depth; drop dead Live ranged API |
| `Lyra/Preview/MarkdownBlockRow.swift` | render ordinal/depth |
| `Lyra/Preview/NotePDFExporter.swift` | pagination, inline MD, images, lists |
| `Scripts/package-dmg.sh`, `Scripts/smoke.sh`, `Scripts/xcode-test.sh` | sign + guards + lean smoke |
| `.github/workflows/release.yml` | tag ↔ MARKETING_VERSION |
| `Lyra.xcodeproj/project.pbxproj`, `Lyra/Info.plist` | 0.6.2, CFBundleVersion, warnings-as-errors |
| `LyraTests/*` | real behavior tests |
| `README.md`, `CONTRIBUTING.md`, `docs/ci.md`, `.github/PULL_REQUEST_TEMPLATE.md` | user-facing truth |

---

## Task A: Reconcile plan doc + freeze WIP inventory

**Files:**
- Modify: `docs/superpowers/plans/2026-08-04-claude-audit-fixes.md` (replace with this plan’s task list, slimmed)
- Do not change product code

**Steps:**
- [ ] Confirm `git status` is on `fix/claude-audit-critical` and smoke still passes: `bash Scripts/smoke.sh`
- [ ] Write the in-repo plan copy so later agents have one source of truth
- [ ] No product commit required (or `docs: plan for Claude audit fixes` if preferred)

---

## Task 1: Rename trap + New Note open (audit #01, #02)

**Files:** `VaultStore.swift`, `ContentView.swift`, `EditorViewModel.swift`, `VaultStoreRenameTests.swift`, `EditorViewModelTests.swift`

**Interfaces:**
- Produces: `@discardableResult func renameSelected(to: String) -> URL?`
- Produces: `EditorViewModel.relocate(to: URL)`
- Produces: private `pendingSelection` applied only after successful scan assigns `rootNode`

**Already on WIP — verify these behaviors:**

1. Rename returns destination immediately (before refresh lands).
2. ContentView uses returned URL; relocates when `openPath == oldPath` OR `openPath.hasPrefix(oldPath + "/")` (never bare `hasPrefix(oldPath)`).
3. `relocate` does not write disk.
4. `close()` succeeds when the open path no longer exists (escape hatch).
5. `createNote` / `createFolder` set `pendingSelection` + `lastCreateParentPath`, never eager `selection =` before tree has the node.
6. Tests cover return URL, relocate no-write, close when parent removed.

**Residual to watch:**
- After `pendingSelection` applies, `handleSelectionChange` must open the note (selection change fires once tree has node).
- If tests race on async refresh, seed `rootNode` as the existing rename test does — do not add sleeps >2s.

**Commit (only these files if possible):**
```bash
git add Lyra/Vault/VaultStore.swift Lyra/App/ContentView.swift Lyra/Editor/EditorViewModel.swift \
  LyraTests/VaultStoreRenameTests.swift LyraTests/EditorViewModelTests.swift
# Note: ContentView/EditorViewModel also contain later-task code — prefer one commit per logical
# cluster only if you can stage hunks; otherwise use Task 9 “split commits carefully” guidance.
git commit -m "$(cat <<'EOF'
fix: rename relocates open note; create opens after scan lands

EOF
)"
```

If hunks are too interleaved, **skip per-task commits until Task 9** and only verify here.

---

## Task 2: Editor durability (audit #05, #06, #10, #15)

**Files:** `EditorViewModel.swift`, `ContentView.swift`, `LyraApp.swift`, `EditorViewModelTests.swift`

**Requirements (verify WIP):**
1. Disk identity = abs mtime delta (>0.001s) + file size; re-stat with cache cleared.
2. Missing path → `hasMissingFile` (own dialog: Save Here / Close / Cancel); never silent recreate on autosave.
3. Cancel conflict → `deferConflict()` sets `conflictDeferred`, suspends autosave; does **not** update disk snapshot to accept theirs.
4. Autosave failure → `lastSaveFailed` + `lastError`; ContentView surfaces once via `hasError`; toolbar shows failed / paused / unsaved.
5. `VaultStore` + `EditorViewModel` owned by `LyraApp`; `AppDelegate.applicationShouldTerminate` cancels quit when save fails and posts `.lyraQuitSaveFailed`.
6. Tests: backdated write, missing file no recreate, defer, failed save sticky.

**Do not:** make close discard dirty buffers on generic I/O failure (disk full) — only missing path is the escape hatch.

**Commit message:** `fix: fail-closed conflicts, quit save guard, autosave errors`

---

## Task 3: Highlight EOF + paste (audit #09, #12)

**Files:** `MarkdownHighlighter.swift`, `MarkdownTextView.swift`, `MarkdownHighlighterTests.swift`

**Requirements (verify WIP):**
1. Clamp caret without `NSIntersectionRange` collapsing `{length,0}` → `{0,0}`.
2. Multi-line paste expands highlight via length delta (not `editedRange` after `textDidChange`).
3. Pasteboard images: raw PNG/TIFF/`NSImage(pasteboard:)` first; URL loads only `url.isFileURL`.
4. Tests assert bold/heading **attributes**, not string length only; caret-at-EOF highlights last paragraph.

**Commit message:** `fix: highlight EOF/paste span; no network on link paste`

---

## Task 4: Scan resilience + Refresh (audit #13, #14)

**Files:** `FileSystemVault.swift`, `ContentView.swift`, `LyraApp.swift`, `FileSystemVaultTests.swift`

**Requirements (verify WIP):**
1. Per-child `do/catch { continue }`; root still throws if root unreadable.
2. Skip packages via `isPackageKey` (do not rely on `skipsPackageDescendants` on `contentsOfDirectory`).
3. Menu **Refresh Vault** + ⌘R; rescan when `scenePhase == .active` and vault open.
4. Test: unreadable child does not drop sibling notes.

**Commit message:** `fix: resilient vault scan; Refresh (⌘R)`

---

## Task 5: Release signing, versions, smoke (audit #03, #04, #20, #30, #35)

**Files:** `Scripts/package-dmg.sh`, `Scripts/xcode-test.sh`, `Scripts/smoke.sh`, `.github/workflows/release.yml`, `project.pbxproj`, `Info.plist`

**Requirements (verify WIP):**
1. Remove `CODE_SIGNING_ALLOWED=NO`; keep `CODE_SIGN_IDENTITY="-"`; set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`.
2. `MARKETING_VERSION = 0.6.2` all configs; `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`; bump `CURRENT_PROJECT_VERSION`.
3. Release workflow: three-part semver + match `MARKETING_VERSION`; package-dmg asserts app plist version.
4. `assert_under_root` normalizes `..` segments.
5. Lean `smoke.sh`: no hand-maintained Swift file lists; entitlements/deploy/bundle-id/docs/fonts/version uniqueness; optional `codesign` sandbox check if app present.
6. `SWIFT_TREAT_WARNINGS_AS_ERRORS` + `GCC_TREAT_WARNINGS_AS_ERRORS` on shared Debug/Release project configs.
7. **Do not** enable strict concurrency / Swift 6.

**Commit message:** `fix(ci): ad-hoc sandbox sign, version guards, lean smoke`

---

## Task 6: PDF + ordered lists (audit #07, #08, #11, #25, #26)

**Files:** `NotePDFExporter.swift`, `MarkdownPreviewBlocks.swift`, `MarkdownBlockRow.swift`, PDF/preview tests

**Requirements (verify WIP):**
1. Text/code can span pages (`drawTextSpanning` / line-based code chunks); no silent clip past page bottom.
2. Images scale by width **and** height (`min(1, wScale, hScale)`).
3. PDF inline Markdown via same `prepareInlineMarkdown` + `inlinePresentationIntent` fonts (not flat string).
4. `listItem(text:ordinal:depth:)` — ordered keep numbers; depth = leading whitespace/2.
5. PDFKit tests extract real text; multi-page code keeps last line; no literal `**` in export.
6. Drop dead `parseRanged` / `replacing` Live helpers and their tests (Live is gone).

**Known residual OK for this PR:** tall single list-item / quote may still not soft-wrap across pages as elegantly as paragraphs — only fix if trivial while touching the draw path.

**Commit message:** `fix: PDF pagination/inline MD; ordered list depth`

---

## Task 7: Menus (audit #33 + part of #31)

**Files:** `LyraApp.swift`, `ContentView.swift`

**Requirements (verify WIP):**
1. File menu: New Note (⌘N), New Folder, Open Vault (⌘O), Refresh (⌘R).
2. View menu: Toggle Source/Reading (⌘E).
3. Export PDF disabled when no open note.
4. Toolbar buttons must **not** re-declare the same shortcuts (menu owns them).

**Commit message:** `fix: command menus for vault and view actions`

---

## Task 8: Docs + checklist (audit #18, #31, #36 + README invariants)

**Files:** `README.md`, `CONTRIBUTING.md`, `docs/ci.md`, `.github/PULL_REQUEST_TEMPLATE.md`  
Optional one-liner in `docs/architecture.md` only if Refresh / conflict behavior needs a structural note.

**Requirements — write concrete copy changes:**

1. **README**
   - Badge / release examples: `0.6.2` / `v0.6.2` (not `0.5.0`).
   - Shortcuts table: add **⌘R Refresh vault**; keep ⌘O/N/S/E.
   - Document conflict: Cancel pauses autosave; quit blocked until resolved or save succeeds.
   - Document missing-file dialog (moved/deleted outside Lyra).
   - Document save indicator (unsaved / failed / paused).
   - Install: **remove** “right-click → Open” as the supported Gatekeeper bypass. State clearly: CI DMGs are **ad-hoc signed for App Sandbox**, **not notarized**; on macOS 15+ users may need System Settings → Privacy & Security → Open Anyway, or build from source. Do not claim Gatekeeper is solved.
   - Release blurb: stop saying “unsigned DMG” if we now ad-hoc sign; say “ad-hoc signed, not notarized”.

2. **docs/ci.md**
   - Same version numbers and signing wording.
   - Note version-tag must match `MARKETING_VERSION`.
   - Note warnings-as-errors; strict concurrency deferred.

3. **CONTRIBUTING.md**
   - Retitle checklist to current version (`v0.6` / `0.6.2`).
   - Add required steps (keep total ~20; mark optional if longer):
     - Rename open note → one file in Finder with all text
     - Rename folder while note inside open → not stuck; typing still saves
     - New Note opens immediately
     - Conflict Cancel then ⌘Q → quit blocked / warned
     - Move/delete open note in Finder → missing-file warning, not silent recreate
     - Refresh (⌘R) after external file add
     - Unreadable child folder → rest of sidebar still shows
     - PDF: long code fence multi-page + bold not `**`
   - Remove any Live-mode steps.

4. **`.github/PULL_REQUEST_TEMPLATE.md`**
   - Change `Source/Live/Reading` → `Source/Reading`.

5. Do **not** delete historical specs under `docs/superpowers/plans/` or `.superpowers/` — they are design history.

**Commit message:** `docs: audit fix behavior, 0.6.2, Gatekeeper honesty`

---

## Task 9: Residual polish, commit strategy, verify, PR

### 9a Residual code hygiene
- Grep for: `CODE_SIGNING_ALLOWED=NO`, `parseRanged`, `LivePreview`, old `.listItem("` shape, `Source/Live`
- Fix only hits in **live** product/docs (not historical plans)
- Optional freebie: if `release.yml` still floats `softprops/action-gh-release` on a moving major tag, pin a full commit SHA only if you already edit that file — otherwise leave as **DEFERRED #19**

### 9b Commit strategy (pick one; prefer B if hunks are messy)

**A — Logical commits (best history):** stage by task file sets / `git add -p` into Tasks 1–8 messages above.

**B — Two commits (pragmatic if interleaved):**
1. `fix: address Claude audit critical/high findings` — all product + tests + scripts + project
2. `docs: version 0.6.2, refresh, conflict, signing wording` — README/CONTRIBUTING/ci/template/plan

Do **not** force-push `main`. Branch may be rewritten only if it was never pushed; if already on origin, add commits only.

### 9c Verify
```bash
bash Scripts/smoke.sh
# On a Mac:
bash Scripts/xcode-test.sh
```
Expected: smoke PASSED; all unit tests green (including new PDFKit / highlighter / vault tests).

### 9d Open PR
```bash
git push -u origin HEAD
gh pr create --title "fix: Claude audit critical/high fixes (0.6.2)" --body "$(cat <<'EOF'
## Summary
- Fix rename/create race (stale tree): relocate open notes; open new notes after scan lands
- Fail-closed disk conflicts, missing-file dialog, quit save guard, autosave error UX
- Highlight EOF/paste; never fetch https on image paste
- Resilient vault scan + Refresh (⌘R)
- Ad-hoc sign release builds so App Sandbox applies; version tag ↔ MARKETING_VERSION 0.6.2
- PDF pagination / inline Markdown / ordered lists; honest unit tests
- Command menus; docs + manual checklist

## Audit IDs addressed
01–15, 18, 20, 25–27, 30–31 (partial), 33, 35–36

## Explicitly deferred
16 context-menu wrong row · 17 DMG-on-every-PR · 19 pin gh-release action · 21–24 parser polish/perf · 28–29 extra tests · 32 full doc corpus dedupe · 34 cosmetic assets · Swift 6 strict concurrency · Developer ID notarization

## Test plan
- [x] `bash Scripts/smoke.sh`
- [ ] `bash Scripts/xcode-test.sh` (macOS)
- [ ] Manual: rename folder with open note; New Note opens; Cancel conflict + ⌘Q; Refresh; PDF multipage

EOF
)"
```

---

## Explicitly DEFERRED (do not implement in this PR)

| ID | Topic | Why |
|----|--------|-----|
| 16 | Context menu wrong row | Selection UX; easy to make worse |
| 17 | DMG build on every PR | CI cost; release path guarded enough |
| 19 | Pin `action-gh-release` SHA | Supply-chain; optional later |
| 21–24 | Front matter / regex cache / blockquote / full binding perf | Parser/perf day-project |
| 28–29 | Autosave debounce suite / full CRUD store suite | Beyond added tests |
| 32 | Full docs dedupe | Partial via Task 8 only |
| 34 | Orphan assets / .gitignore trim | Cosmetic |
| — | Swift 6 strict concurrency | Audit: false positives today |
| — | Notarization / Developer ID | Needs Apple program; not “flip a flag” |
| — | FSEvents live vault watch | YAGNI; Refresh is enough |

---

## Subagent strategy (recommended)

One fresh implementer subagent **per task** (A → 9), then a quick review gate:

1. **Implementer** receives only that task’s section + global constraints + “WIP may already exist — verify first”.
2. **Reviewer** (spec compliance + code quality, can be same session checklist): task requirements met? no scope creep? tests real?
3. Do **not** parallelize Tasks 1–2–7 (shared `ContentView` / `LyraApp` / `EditorViewModel`). Safe parallel only if splitting pure docs (Task 8) after code freezes — still prefer serial on this branch.
4. After Task 9, run `verification-before-completion` mentally: no success claim without smoke (and xcode-test on Mac).

**Alternative:** single-session `executing-plans` if you want fewer handoffs — same task order, batch commits at Task 9.

---

## Spec coverage checklist (self-review)

| Audit # | Task |
|---------|------|
| 01, 02 | 1 |
| 05, 06, 10, 15 | 2 |
| 09, 12 | 3 |
| 13, 14 | 4 |
| 03, 04, 20, 30, 35 | 5 |
| 07, 08, 11, 25, 26 | 6 |
| 33, 31 menus | 7 |
| 18, 31 docs, 36 | 8 |
| 27 (tests), residual | 2/3/6 + 9 |
| Deferred IDs | table above |

---

## Execution handoff

Plan complete. Two ways to run it:

1. **Subagent-driven (recommended)** — fresh agent per task, review between tasks; best for the interleaved WIP on this branch.
2. **Inline execution** — same session, Tasks A→9 with checkpoints.

**Recommended path given current state:** Task A → serial verify Tasks 1–7 against WIP → Task 8 docs (the real remaining work) → Task 9 commits + PR. On a Mac, run `xcode-test.sh` before merge.
