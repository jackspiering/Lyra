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

    /// Tab bar label (filename stem, or “New Tab”).
    var title: String {
        if let url = editor.fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "New Tab"
    }

    init(id: UUID = UUID(), editor: EditorViewModel = EditorViewModel()) {
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

    /// Opens `url` in the active tab. Returns `false` if a dirty save failed.
    @discardableResult
    func openInActiveTab(url: URL) -> Bool {
        let tab = selectedTab ?? {
            let t = NoteTab()
            tabs = [t]
            selectedTabID = t.id
            return t
        }()
        if tab.editor.fileURL?.path == url.path {
            return true
        }
        return tab.editor.open(url: url)
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
