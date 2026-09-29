import Foundation
import Observation

/// A note rename that left `[[links]]` in other notes pointing at the old name.
struct PendingLinkUpdate: Identifiable {
    let id = UUID()
    let oldURL: URL
    let newStem: String
    let sources: [Backlink]
    /// Resolver from before the rename, which still resolves the old name.
    let resolver: WikiLinkResolver

    /// Question shown before rewriting the links.
    var message: String {
        let oldStem = oldURL.deletingPathExtension().lastPathComponent
        let notes = sources.count == 1 ? "1 note links" : "\(sources.count) notes link"
        return "\(notes) to “\(oldStem)”. Point those links at “\(newStem)”?"
    }
}

/// Renames for one vault window, from the sidebar or the title field: flush
/// every tab, rename on disk, move open tabs to the new path, then offer to
/// point `[[links]]` at a renamed note.
@MainActor
@Observable
final class RenameFlow {
    /// Link update waiting for the user's answer; nil when idle. Settable so
    /// the window shell can bind it to an alert.
    var pendingLinkUpdate: PendingLinkUpdate?

    private let store: VaultStore
    private let tabs: NoteTabController
    /// Surfaces a failed pre-rename save; owned by the window shell.
    private let flushError: (EditorViewModel) -> Void

    init(
        store: VaultStore,
        tabs: NoteTabController,
        flushError: @escaping (EditorViewModel) -> Void
    ) {
        self.store = store
        self.tabs = tabs
        self.flushError = flushError
    }

    /// Sidebar inline rename. Returns `false` when nothing was renamed.
    func rename(_ node: VaultNode, to newName: String) -> Bool {
        rename(at: node.url, isDirectory: node.isDirectory, to: newName)
    }

    /// Title field commit for the note at `url`: rename the file. The first
    /// heading is not the name. Returns `false` when nothing was renamed.
    func commitTitle(_ newTitle: String, for url: URL?) -> Bool {
        guard let url, tabs.tabs.contains(where: { $0.editor.fileURL?.path == url.path }) else {
            // That note is no longer open here; nothing to rename.
            return false
        }
        switch NoteTitle.stem(forTitle: newTitle) {
        case .invalid(let detail):
            store.present(context: .rename, message: detail)
            return false
        case .ok(let stem):
            guard stem != url.deletingPathExtension().lastPathComponent else { return true }
            return rename(at: url, isDirectory: false, to: stem + ".md")
        }
    }

    /// Rewrite links in every note that pointed at the renamed one. Open
    /// notes change in their tab (autosave writes them); closed notes go
    /// through the normal save path, so conflict and vault checks apply.
    func applyLinkUpdate(_ update: PendingLinkUpdate) {
        var failures = 0
        for source in update.sources {
            if let tab = tabs.tabs.first(where: { $0.editor.fileURL?.path == source.url.path }) {
                if let rewritten = update.resolver.rewritingLinks(
                    in: tab.editor.text,
                    from: update.oldURL,
                    toStem: update.newStem
                ) {
                    tab.editor.text = rewritten
                    tab.editor.noteEdited()
                }
                continue
            }
            let editor = EditorViewModel()
            editor.vaultRoot = store.rootURL
            guard editor.open(url: source.url) else {
                failures += 1
                continue
            }
            guard let rewritten = update.resolver.rewritingLinks(
                in: editor.text,
                from: update.oldURL,
                toStem: update.newStem
            ) else { continue }
            editor.text = rewritten
            editor.isDirty = true
            if !editor.saveIfNeeded() {
                failures += 1
            }
        }
        if failures > 0 {
            store.present(
                .rename,
                detail: "Lyra couldn't update links in \(failures == 1 ? "1 note" : "\(failures) notes"). "
                    + "Those links still use the old name."
            )
        }
        store.refresh()
    }

    /// Flush editors, rename on disk, relocate open tabs, and offer to point
    /// `[[links]]` at a renamed note.
    private func rename(at url: URL, isDirectory: Bool, to newName: String) -> Bool {
        for tab in tabs.tabs {
            guard tab.editor.saveIfNeeded() else {
                flushError(tab.editor)
                return false
            }
        }
        // Capture links to the old name before the rescan forgets it.
        let resolver = store.linkResolver
        let linkSources = isDirectory ? [] : store.backlinks(to: url, liveBodies: tabs.liveBodies())
        // Rename by path, not by moving the sidebar selection: a selection change
        // would try to open the old path after the file has moved.
        guard let newURL = store.renameItem(at: url, to: newName) else {
            return false
        }
        // Same name (`Note` for `Note.md`): nothing moved, so no link update.
        guard newURL.path != url.path else { return true }
        tabs.relocateOpenNotes(oldPath: url.path, newURL: newURL)
        if !linkSources.isEmpty {
            pendingLinkUpdate = PendingLinkUpdate(
                oldURL: url,
                newStem: newURL.deletingPathExtension().lastPathComponent,
                sources: linkSources,
                resolver: resolver
            )
        }
        return true
    }
}
