import Foundation
import Observation

/// One in-window note tab: empty (`fileURL == nil`) or a note editor.
@MainActor
@Observable
final class NoteTab: Identifiable {
    let id: UUID
    let editor: EditorViewModel

    /// Mirrors `editor.fileURL`; `nil` means empty tab.
    var fileURL: URL? { editor.fileURL }

    /// Tab bar label: H1 or filename stem via `NoteTitle`, or “New Tab” when empty.
    var title: String {
        if editor.fileURL != nil {
            return NoteTitle.displayTitle(markdown: editor.text, fileURL: editor.fileURL)
        }
        return "New Tab"
    }

    /// Create an empty tab. Editor is created in the init body so the default
    /// argument does not evaluate `EditorViewModel()` in a nonisolated context
    /// (Swift concurrency error under Xcode 16).
    init(id: UUID = UUID()) {
        self.id = id
        self.editor = EditorViewModel()
    }

    init(id: UUID = UUID(), editor: EditorViewModel) {
        self.id = id
        self.editor = editor
    }
}

/// Manages note tabs for one vault window. Always keeps at least one tab.
@MainActor
@Observable
final class NoteTabController {
    var tabs: [NoteTab] = []
    var selectedTabID: NoteTab.ID?

    var selectedTab: NoteTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var selectedEditor: EditorViewModel {
        selectedTab?.editor ?? tabs[0].editor
    }

    /// True if any open note in this window has unsaved changes.
    var anyDirty: Bool {
        tabs.contains { $0.editor.isDirty }
    }

    init() {
        let first = NoteTab()
        tabs = [first]
        selectedTabID = first.id
    }

    func select(_ id: NoteTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    /// Appends an empty tab and selects it. Caller registers the editor with `AppSession`.
    @discardableResult
    func newEmptyTab() -> NoteTab {
        let tab = NoteTab()
        tabs.append(tab)
        selectedTabID = tab.id
        return tab
    }

    /// If any tab already shows this path, select it. Avoids dual-opening the same note.
    @discardableResult
    func selectOpenNote(path: String) -> Bool {
        guard let existing = tabs.first(where: { $0.editor.fileURL?.path == path }) else {
            return false
        }
        selectedTabID = existing.id
        return true
    }

    /// Opens `url` in the active tab. Returns `false` if a dirty save failed.
    /// If the controller had no tabs, synthesizes one and invokes `onCreated` so the caller can register AppSession.
    @discardableResult
    func openInActiveTab(url: URL, onCreated: ((NoteTab) -> Void)? = nil) -> Bool {
        let tab: NoteTab
        if let selected = selectedTab {
            tab = selected
        } else {
            let t = NoteTab()
            tabs = [t]
            selectedTabID = t.id
            onCreated?(t)
            tab = t
        }
        if tab.editor.fileURL?.path == url.path {
            return true
        }
        return tab.editor.open(url: url)
    }

    /// Open `url` in a brand-new tab (caller registers AppSession). Returns false if open failed.
    /// If already open, selects that tab. On open failure, removes the new tab and restores selection.
    @discardableResult
    func openInNewTab(url: URL, onCreated: ((NoteTab) -> Void)? = nil) -> Bool {
        if selectOpenNote(path: url.path) { return true }
        let previousID = selectedTabID
        let tab = NoteTab()
        tabs.append(tab)
        selectedTabID = tab.id
        if tab.editor.open(url: url) {
            // Register only after open succeeds so rollback does not leave a dangling AppSession entry.
            onCreated?(tab)
            return true
        }
        // Roll back failed tab
        tabs.removeAll { $0.id == tab.id }
        selectedTabID = previousID
        return false
    }

    /// Closes the tab after flushing its editor. Last tab becomes empty (vault stays open).
    /// Returns `false` if save failed (tab left open). Unregister only when the tab is removed.
    @discardableResult
    func close(id: NoteTab.ID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return true }
        let tab = tabs[index]
        guard tab.editor.close() else { return false }

        if tabs.count == 1 {
            // Keep a single empty tab so the vault sidebar remains.
            selectedTabID = tab.id
            return true
        }

        tabs.remove(at: index)
        if selectedTabID == id {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }
        return true
    }

    /// Editors for quit-save / window teardown.
    func allEditors() -> [EditorViewModel] {
        tabs.map(\.editor)
    }

    /// After a rename/move on disk, point any matching open editors at the new path.
    func relocateOpenNotes(oldPath: String, newURL: URL) {
        for tab in tabs {
            guard let openPath = tab.editor.fileURL?.path else { continue }
            if openPath == oldPath {
                tab.editor.relocate(to: newURL)
            } else if openPath.hasPrefix(oldPath + "/") {
                let suffix = String(openPath.dropFirst(oldPath.count))
                let relocated = URL(fileURLWithPath: newURL.path + suffix)
                tab.editor.relocate(to: relocated)
            }
        }
    }
}
