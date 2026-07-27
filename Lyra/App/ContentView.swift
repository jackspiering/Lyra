import AppKit
import SwiftUI

struct ContentView: View {
    @State private var store = VaultStore()
    @State private var editor = EditorViewModel()
    @AppStorage("lyra.previewVisible") private var previewVisible = true
    @State private var renameTarget: VaultNode?
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var lastOpenedPath: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.rootURL == nil {
                OpenVaultView { url in
                    Task { await store.openVault(at: url) }
                }
            } else {
                vaultWorkspace
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                Task { await editor.saveIfNeeded() }
            }
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
            Task { await handleSelectionChange(newValue) }
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
                Task {
                    await editor.close()
                    await store.deleteSelected()
                    lastOpenedPath = nil
                }
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
                        Task { await store.createNote() }
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .help("New Note")
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        Task { await store.createFolder() }
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .help("New Folder")
                }
            }
        } detail: {
            detailPane
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            pickVault()
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

                        Button {
                            Task { await editor.saveIfNeeded() }
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .keyboardShortcut("s", modifiers: .command)
                    }
                }
        }
    }

    private var detailPane: some View {
        HSplitView {
            EditorView(viewModel: editor)
                .frame(minWidth: 280)
            if previewVisible {
                MarkdownPreviewView(text: editor.text) { linkText in
                    Task { await openWikiLink(linkText) }
                }
                .frame(minWidth: 240)
            }
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
                    Task {
                        let oldPath = node.url.path
                        await editor.saveIfNeeded()
                        await store.renameSelected(to: renameText)
                        if editor.document?.url.path == oldPath,
                           let newURL = store.selectedFileURL() {
                            await editor.open(url: newURL)
                            lastOpenedPath = newURL.path
                        }
                        renameTarget = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func handleSelectionChange(_ newValue: VaultNode.ID?) async {
        guard let newValue,
              let root = store.rootNode,
              let node = FileSystemVault.findNode(id: newValue, in: root),
              !node.isDirectory else {
            if store.selectedFileURL() == nil {
                await editor.close()
                lastOpenedPath = nil
            }
            return
        }
        if lastOpenedPath == node.url.path { return }
        await editor.open(url: node.url)
        lastOpenedPath = node.url.path
    }

    private func openWikiLink(_ text: String) async {
        guard let url = store.resolveWikiLink(text) else { return }
        await editor.saveIfNeeded()
        store.openNote(url: url)
        await editor.open(url: url)
        lastOpenedPath = url.path
    }

    private func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await editor.close()
                lastOpenedPath = nil
                await store.openVault(at: url)
            }
        }
    }
}
