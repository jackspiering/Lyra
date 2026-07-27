import SwiftUI

struct ContentView: View {
    @State private var store = VaultStore()
    @State private var editor = EditorViewModel()
    @AppStorage("lyra.previewVisible") private var previewVisible = true
    @State private var renameTarget: VaultNode?
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.rootURL == nil {
                ContentUnavailableView {
                    Label("No Vault Open", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Open a folder of Markdown files to begin.")
                } actions: {
                    Button("Open Vault…") {
                        if let url = VaultFolderPicker.pick(
                            message: "Choose a folder to use as a Lyra vault"
                        ) {
                            store.openVault(at: url)
                        }
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                vaultWorkspace
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { editor.saveIfNeeded() }
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.selection) { _, newValue in
            handleSelectionChange(newValue)
        }
        .sheet(item: $renameTarget) { node in
            renameSheet(node)
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                editor.close()
                store.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This item will be moved to the Trash.")
        }
    }

    private var vaultWorkspace: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                renameTarget: $renameTarget,
                showDeleteConfirm: $showDeleteConfirm
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        store.createNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        store.createFolder()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
            }
        } detail: {
            HSplitView {
                editorPane.frame(minWidth: 280)
                if previewVisible {
                    MarkdownPreviewView(
                        text: editor.text,
                        noteDirectory: editor.fileURL?.deletingLastPathComponent(),
                        vaultRoot: store.rootURL
                    ) { openWikiLink($0) }
                        .frame(minWidth: 240)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        if let url = VaultFolderPicker.pick() {
                            editor.close()
                            store.openVault(at: url)
                        }
                    } label: {
                        Label("Open Vault", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Button {
                        previewVisible.toggle()
                    } label: {
                        Label("Toggle Preview", systemImage: "sidebar.right")
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            }
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        if editor.fileURL != nil {
            MarkdownTextView(text: $editor.text) { editor.noteEdited() }
        } else {
            ContentUnavailableView(
                "Select a note",
                systemImage: "doc.text",
                description: Text("Choose a Markdown file from the sidebar, or create a new note.")
            )
        }
    }

    private func renameSheet(_ node: VaultNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename").font(.headline)
            TextField("Name", text: $renameText)
                .onAppear { renameText = node.name }
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                Button("Rename") {
                    let oldPath = node.url.path
                    editor.saveIfNeeded()
                    store.renameSelected(to: renameText)
                    if editor.fileURL?.path == oldPath, let newURL = store.selectedFileURL() {
                        editor.open(url: newURL)
                    }
                    renameTarget = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

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
        }
    }

    private func openWikiLink(_ text: String) {
        guard let url = store.resolveWikiLink(text) else { return }
        editor.saveIfNeeded()
        store.selection = url.path
        editor.open(url: url)
    }
}
