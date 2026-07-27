import SwiftUI

struct SidebarView: View {
    @Bindable var store: VaultStore
    @Binding var renameTarget: VaultNode?
    @Binding var showDeleteConfirm: Bool

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
