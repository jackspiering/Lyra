import SwiftUI

struct SidebarView: View {
    @Bindable var store: VaultStore
    /// Save editor, `renameSelected`, relocate open note. Returns `true` on success.
    var onCommitRename: (VaultNode, String) -> Bool = { _, _ in false }
    var onRequestDelete: () -> Void = {}
    var onNewNote: () -> Void = {}
    var onExportNotePDF: (VaultNode) -> Void = { _ in }

    @State private var query: String = ""
    @State private var renamingID: VaultNode.ID?
    @State private var renameDraft: String = ""
    /// When true, focus-loss must not commit (Escape / selection change / successful commit cleanup).
    @State private var suppressFocusCommit = false
    @FocusState private var renameFieldFocused: Bool

    private var displayRoot: VaultNode? {
        guard let root = store.rootNode else { return nil }
        return VaultSearch.filteredTree(root: root, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            scanLimitsBanner
            Divider()
            treeList
        }
    }

    @ViewBuilder
    private var scanLimitsBanner: some View {
        if store.scanDidTruncate || store.scanSkippedLargeNotes {
            VStack(alignment: .leading, spacing: 2) {
                if store.scanDidTruncate {
                    Text("Nested folders deeper than 64 levels were skipped.")
                }
                if store.scanSkippedLargeNotes {
                    Text("Notes larger than 2 MB were left out of search and backlinks.")
                }
            }
            .font(LyraFonts.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var treeList: some View {
        List(selection: $store.selection) {
            if let root = displayRoot {
                OutlineGroup(root.children ?? [], id: \.id, children: \.children) { node in
                    row(for: node)
                        .tag(node.id)
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
                    .accessibilityLabel("Rename \(node.name)")
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(node) }
                    .onExitCommand { cancelRename() }
            }
        } else {
            // macOS List(selection:) often misses hits on Label title text — only padding
            // beside the glyph/text selects. Build an explicit full-row hit target and
            // set selection ourselves (List binding still highlights via .tag).
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .accessibilityLabel(node.isDirectory ? "Folder \(node.name)" : "Note \(node.name)")
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .contentShape(Rectangle())
            // Register double-tap before single-tap so rename wins on double-click.
            .onTapGesture(count: 2) {
                store.selection = node.id
                beginRename(node)
            }
            .onTapGesture(count: 1) {
                store.selection = node.id
            }
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
