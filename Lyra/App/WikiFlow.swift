import Foundation
import Observation

/// Wiki-link navigation for one vault window. Resolution routes the unique
/// match straight through the window's tab rules; ambiguous matches and
/// unresolved names raise the pick-or-create sheet instead of guessing.
/// Sidebar activation and Go to File reuse the same tab rules via `activate`,
/// so every path into a note behaves identically.
@MainActor
@Observable
final class WikiFlow {
    /// Active pick-or-create confirmation sheet; nil when idle.
    private(set) var prompt: WikiFollowPrompt?

    private let store: VaultStore
    private let tabs: NoteTabController
    /// Surfaces a failed pre-navigation save; owned by the window shell.
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

    /// Click or command-click on `[[text]]` inside the linking note.
    func followLink(_ text: String, from linkingNoteURL: URL?) {
        switch store.resolveWikiLink(text) {
        case .unique(let url):
            open(url)
        case .ambiguous(let candidates):
            prompt = .pick(query: text, candidates: candidates)
        case .unresolved:
            guard let root = store.rootURL,
                  let dest = WikiLinkSyntax.destinationURL(
                    target: WikiLinkSyntax.parseInner(text).target,
                    vaultRoot: root,
                    linkingNoteURL: linkingNoteURL
                  ) else {
                return
            }
            prompt = .create(query: text, destination: dest)
        }
    }

    /// Open a resolved destination (picker pick, backlink, search hit).
    func open(_ url: URL) {
        if tabs.selectOpenNote(path: url.path) {
            store.selection = url.path
            return
        }
        guard tabs.selectedEditor.saveIfNeeded() else {
            flushError(tabs.selectedEditor)
            return
        }
        store.selection = url.path
        activate(url)
    }

    /// Sheet confirmed creating the file for an unresolved link.
    func create(at dest: URL) {
        guard tabs.selectedEditor.saveIfNeeded() else {
            flushError(tabs.selectedEditor)
            return
        }
        guard store.createNote(at: dest) else { return }
        store.selection = dest.path
        activate(dest)
    }

    func cancelPrompt() {
        prompt = nil
    }

    /// Open a note from sidebar / wiki: already open → select; empty active
    /// → fill; else new tab.
    func activate(_ url: URL) {
        if tabs.selectOpenNote(path: url.path) { return }
        if tabs.selectedEditor.fileURL == nil {
            // empty active tab — fill it
            _ = tabs.openInActiveTab(url: url) { created in
                AppSession.shared.register(editor: created.editor, store: store)
            }
            // Whether the fill succeeded or not, surface any failure from the previous save/open.
            flushError(tabs.selectedEditor)
            return
        }
        if tabs.selectedEditor.fileURL?.path == url.path { return }
        // Active has another note → new tab
        let ok = tabs.openInNewTab(
            url: url,
            onCreated: { created in
                AppSession.shared.register(editor: created.editor, store: store)
            },
            onFailed: { failed in
                self.flushError(failed)
            }
        )
        if ok {
            flushError(tabs.selectedEditor)
        } else {
            // Restored previous tab after rollback — align sidebar to it.
            store.selection = tabs.selectedTab?.editor.fileURL?.path
        }
    }
}
