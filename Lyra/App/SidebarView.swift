import SwiftUI

struct SidebarView: View {
    @Bindable var store: VaultStore
    @Binding var renameTarget: VaultNode?
    @Binding var showDeleteConfirm: Bool
    var onExportNotePDF: (VaultNode) -> Void = { _ in }
    var onExportFolderSeparate: (VaultNode) -> Void = { _ in }
    var onExportFolderCombined: (VaultNode) -> Void = { _ in }

    var body: some View {
        List(selection: $store.selection) {
            if let root = store.rootNode {
                Section(root.name) {
                    OutlineGroup(root.children ?? [], id: \.id, children: \.children) { node in
                        Label(
                            node.name,
                            systemImage: node.isDirectory ? "folder" : "doc.text"
                        )
                        .tag(node.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: VaultNode.ID.self) { ids in
            if let id = ids.first,
               let root = store.rootNode,
               let node = FileSystemVault.findNode(id: id, in: root) {
                if node.isDirectory {
                    Button("New Note") {
                        store.selection = id
                        store.createNote()
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
                    store.selection = id
                    renameTarget = node
                }
                Button("Delete…", role: .destructive) {
                    store.selection = id
                    showDeleteConfirm = true
                }
            }
        }
    }
}
