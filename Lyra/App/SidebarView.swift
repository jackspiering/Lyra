import SwiftUI

struct SidebarView: View {
    @Bindable var store: VaultStore
    /// Save editor, `renameSelected`, relocate open note. Returns `true` on success.
    var onCommitRename: (VaultNode, String) -> Bool = { _, _ in false }
    var onRequestDelete: () -> Void = {}
    var onNewNote: () -> Void = {}
    var onExportNotePDF: (VaultNode) -> Void = { _ in }
    var onExportFolderSeparate: (VaultNode) -> Void = { _ in }
    var onExportFolderCombined: (VaultNode) -> Void = { _ in }
    /// Bumped by ContentView when ⌘F / Find in Vault targets this window.
    var searchFocusToken: Int = 0

    @State private var query: String = ""
    @State private var renamingID: VaultNode.ID?
    @State private var renameDraft: String = ""
    /// When true, focus-loss must not commit (Escape / selection change / successful commit cleanup).
    @State private var suppressFocusCommit = false
    @FocusState private var renameFieldFocused: Bool
    @FocusState private var searchFieldFocused: Bool

    private var displayRoot: VaultNode? {
        guard let root = store.rootNode else { return nil }
        return VaultSearch.filteredTree(root: root, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            treeList
        }
        .onChange(of: searchFocusToken) { _, _ in
            searchFieldFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var treeList: some View {
        List(selection: $store.selection) {
            if let root = displayRoot {
                Section(root.name) {
                    OutlineGroup(root.children ?? [], id: \.id, children: \.children) { node in
                        row(for: node)
                            .tag(node.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onKeyPress(.return) {
            handleReturnKey()
        }
        .onChange(of: store.selection) { _, newValue in
            if let renamingID, renamingID != newValue {
                cancelRename()
            }
        }
        .onChange(of: renameFieldFocused) { _, focused in
            // Finder commits when the field loses focus (click elsewhere), not only on Return.
            guard !focused else { return }
            if suppressFocusCommit {
                suppressFocusCommit = false
                return
            }
            guard let id = renamingID,
                  let root = store.rootNode,
                  let node = FileSystemVault.findNode(id: id, in: root) else {
                return
            }
            commitRename(node)
        }
        // Selection menu (rows). Empty-area New Note/Folder uses the view-level menu below.
        .contextMenu(forSelectionType: VaultNode.ID.self) { ids in
            if let id = ids.first,
               let root = store.rootNode,
               let node = FileSystemVault.findNode(id: id, in: root) {
                if node.isDirectory {
                    Button("New Note") {
                        store.selection = id
                        onNewNote()
                    }
                    Button("New Folder") {
                        store.selection = id
                        store.createFolder()
                    }
                    Divider()
                    Button("Export All to Separate PDFs…") {
                        store.selection = id
                        onExportFolderSeparate(node)
                    }
                    Button("Export All to Single PDF…") {
                        store.selection = id
                        onExportFolderCombined(node)
                    }
                    Divider()
                } else {
                    Button("Export PDF…") {
                        store.selection = id
                        onExportNotePDF(node)
                    }
                    Divider()
                }
                Button("Rename…") {
                    beginRename(node)
                }
                Button("Delete…", role: .destructive) {
                    store.selection = id
                    onRequestDelete()
                }
            }
        }
        // Empty/padding right-click: create in selected folder (or vault root via store parent logic).
        .contextMenu {
            Button("New Note") { onNewNote() }
            Button("New Folder") { store.createFolder() }
        }
    }

    @ViewBuilder
    private func row(for node: VaultNode) -> some View {
        if renamingID == node.id {
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(.secondary)
                TextField("", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(node) }
                    .onExitCommand { cancelRename() }
            }
        } else {
            Label(
                node.name,
                systemImage: node.isDirectory ? "folder" : "doc.text"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Double-click renames even when the row was not previously selected.
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    store.selection = node.id
                    beginRename(node)
                }
            )
        }
    }

    private func handleReturnKey() -> KeyPress.Result {
        if renamingID != nil {
            // TextField owns Return while editing (onSubmit).
            return .ignored
        }
        guard let id = store.selection,
              let root = store.rootNode,
              let node = FileSystemVault.findNode(id: id, in: root) else {
            return .ignored
        }
        beginRename(node)
        return .handled
    }

    private func beginRename(_ node: VaultNode) {
        suppressFocusCommit = false
        store.selection = node.id
        renameDraft = node.name
        renamingID = node.id
        DispatchQueue.main.async {
            renameFieldFocused = true
        }
    }

    private func cancelRename() {
        // Only suppress the upcoming focus-loss if the field currently has focus.
        if renameFieldFocused {
            suppressFocusCommit = true
        }
        renamingID = nil
        renameFieldFocused = false
    }

    private func commitRename(_ node: VaultNode) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Return with empty keeps the field; focus-loss with empty cancels.
            if !renameFieldFocused {
                cancelRename()
            }
            return
        }
        if trimmed == node.name {
            cancelRename()
            return
        }
        if onCommitRename(node, trimmed) {
            cancelRename()
        } else {
            // Keep the field open so the user can fix the name or retry after an error.
            DispatchQueue.main.async {
                renameFieldFocused = true
            }
        }
    }
}
