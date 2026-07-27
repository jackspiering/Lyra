import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = VaultStore()
    @State private var editor = EditorViewModel()
    @AppStorage("lyra.noteViewMode") private var noteViewModeRaw = NoteViewMode.source.rawValue
    @State private var renameTarget: VaultNode?
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @Environment(\.scenePhase) private var scenePhase

    private var noteViewMode: NoteViewMode {
        get { NoteViewMode(rawValue: noteViewModeRaw) ?? .source }
        nonmutating set { noteViewModeRaw = newValue.rawValue }
    }

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
        .font(LyraFonts.body)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                _ = editor.saveIfNeeded()
                flushEditorError()
            }
        }
        .alert(
            store.errorTitle ?? "Something went wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.clearError() }
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
        .onReceive(NotificationCenter.default.publisher(for: .lyraSaveNote)) { _ in
            _ = editor.saveIfNeeded()
            flushEditorError()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyraExportPDF)) { _ in
            exportPDF()
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
            noteDetail
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

                        Picker("View", selection: $noteViewModeRaw) {
                            ForEach(NoteViewMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)

                        Button {
                            noteViewMode = noteViewMode.next()
                        } label: {
                            Label("Cycle View Mode", systemImage: "rectangle.split.2x1")
                        }
                        .keyboardShortcut("e", modifiers: .command)
                        .help("Cycle Source → Live → Reading")

                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        .disabled(editor.fileURL == nil)
                        .help("Export current note to PDF")
                    }
                }
        }
    }

    @ViewBuilder
    private var noteDetail: some View {
        if editor.fileURL == nil {
            ContentUnavailableView(
                "Select a note",
                systemImage: "doc.text",
                description: Text("Choose a Markdown file from the sidebar, or create a new note.")
            )
        } else {
            switch noteViewMode {
            case .source, .livePreview:
                MarkdownTextView(
                    text: $editor.text,
                    vaultRoot: store.rootURL,
                    onEdit: { editor.noteEdited() },
                    onPasteError: { store.present(context: .pasteImage, message: $0) }
                )
            case .reading:
                MarkdownPreviewView(
                    text: editor.text,
                    noteDirectory: editor.fileURL?.deletingLastPathComponent(),
                    vaultRoot: store.rootURL,
                    onWikiLink: { openWikiLink($0) }
                )
            }
        }
    }

    private func renameSheet(_ node: VaultNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename").font(LyraFonts.headline)
            TextField("Name", text: $renameText)
                .onAppear { renameText = node.name }
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                Button("Rename") {
                    let oldPath = node.url.path
                    _ = editor.saveIfNeeded()
                    flushEditorError()
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
            flushEditorError()
        }
    }

    private func flushEditorError() {
        guard let last = editor.lastError else { return }
        store.present(error: last.error, context: last.context)
        editor.lastError = nil
    }

    private func openWikiLink(_ text: String) {
        guard let url = store.resolveWikiLink(text) else { return }
        _ = editor.saveIfNeeded()
        flushEditorError()
        store.selection = url.path
        editor.open(url: url)
        flushEditorError()
    }

    private func exportPDF() {
        guard let noteURL = editor.fileURL, let vault = store.rootURL else { return }
        _ = editor.saveIfNeeded()
        flushEditorError()
        do {
            let data = try NotePDFExporter.pdfData(
                markdown: editor.text,
                noteDirectory: noteURL.deletingLastPathComponent(),
                vaultRoot: vault
            )
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = noteURL.deletingPathExtension().lastPathComponent + ".pdf"
            panel.directoryURL = noteURL.deletingLastPathComponent()
            panel.begin { resp in
                guard resp == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    store.present(error: error, context: .exportPDF)
                }
            }
        } catch {
            store.present(error: error, context: .exportPDF)
        }
    }
}
