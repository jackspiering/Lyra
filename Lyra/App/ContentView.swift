import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @AppStorage("lyra.noteViewMode") private var noteViewModeRaw = NoteViewMode.source.rawValue
    @State private var renameTarget: VaultNode?
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var didAlertSaveFailure = false
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
                        openVault()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                vaultWorkspace
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .font(LyraFonts.body)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if store.rootURL != nil {
                    store.refresh()
                }
            } else {
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
        .confirmationDialog(
            "Note changed on disk",
            isPresented: Binding(
                get: { editor.hasExternalConflict },
                set: { if !$0 { editor.hasExternalConflict = false } }
            ),
            titleVisibility: .visible
        ) {
            Button("Keep Mine") {
                if editor.saveIfNeeded(force: true) {
                    // ok
                } else {
                    flushEditorError()
                }
            }
            Button("Reload Theirs") {
                if !editor.reloadFromDisk() {
                    flushEditorError()
                }
            }
            Button("Cancel", role: .cancel) {
                editor.deferConflict()
            }
        } message: {
            Text("This file was modified outside Lyra. Saving would overwrite those changes.")
        }
        .confirmationDialog(
            "Note moved or deleted",
            isPresented: Binding(
                get: { editor.hasMissingFile },
                set: { if !$0 { editor.hasMissingFile = false } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save Here") {
                if !editor.saveIfNeeded(force: true) {
                    flushEditorError()
                }
            }
            Button("Close Note", role: .destructive) {
                // close() allows escape when the path is gone (no silent trap).
                _ = editor.close()
                store.selection = nil
            }
            Button("Cancel", role: .cancel) {
                editor.hasMissingFile = false
                // Suspend autosave so we do not recreate the file every 500ms.
                editor.deferConflict()
            }
        } message: {
            Text("This note was moved or deleted outside Lyra. Save a copy at the old path, or close the note.")
        }
        .onChange(of: store.selection) { _, newValue in
            handleSelectionChange(newValue)
        }
        .onChange(of: editor.hasError) { _, has in
            // Surface autosave failures once; the toolbar indicator covers the ongoing state.
            if has && !didAlertSaveFailure {
                didAlertSaveFailure = true
                flushEditorError()
            }
            if !has {
                didAlertSaveFailure = false
            }
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
                if editor.close() {
                    store.deleteSelected()
                } else {
                    flushEditorError()
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .lyraNewNote)) { _ in
            store.createNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyraNewFolder)) { _ in
            store.createFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyraOpenVault)) { _ in
            openVault()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyraToggleViewMode)) { _ in
            noteViewMode = noteViewMode.next()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyraRefreshVault)) { _ in
            store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyraQuitSaveFailed)) { _ in
            flushEditorError()
            // Re-surface conflict / missing-file dialogs if those blocked the quit.
            // Flags are already set by saveIfNeeded; confirmationDialogs bind to them.
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
                            openVault()
                        } label: {
                            Label("Open Vault", systemImage: "folder")
                        }

                        Picker("View", selection: $noteViewModeRaw) {
                            ForEach(NoteViewMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)

                        Button {
                            noteViewMode = noteViewMode.next()
                        } label: {
                            Label("Toggle View Mode", systemImage: "rectangle.split.2x1")
                        }
                        .help("Toggle Source ↔ Reading")

                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        .disabled(editor.fileURL == nil)
                        .help("Export current note to PDF")

                        if editor.lastSaveFailed {
                            Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .help("Last save failed — press ⌘S to retry")
                        } else if editor.conflictDeferred {
                            Label("Autosave paused", systemImage: "pause.circle")
                                .foregroundStyle(.orange)
                                .help("Conflict deferred — press ⌘S to resolve")
                        } else if editor.isDirty {
                            Label("Unsaved", systemImage: "circle.fill")
                                .foregroundStyle(.secondary)
                                .help("Unsaved changes")
                        }
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
            case .source:
                MarkdownTextView(
                    text: $editor.text,
                    vaultRoot: store.rootURL,
                    noteURL: editor.fileURL,
                    onEdit: { editor.noteEdited() },
                    onPasteError: { store.present(context: .pasteImage, message: $0) }
                )
                // Per-file identity: reset selection, scroll, and undo when switching notes.
                .id(editor.fileURL?.path)
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

    private func openVault() {
        let message = store.rootURL == nil
            ? "Choose a folder to use as a Lyra vault"
            : nil
        if let url = VaultFolderPicker.pick(message: message ?? "Choose a folder to use as a Lyra vault") {
            if store.rootURL == nil || editor.close() {
                store.openVault(at: url)
            } else {
                flushEditorError()
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
                    guard editor.saveIfNeeded() else {
                        flushEditorError()
                        return
                    }
                    guard let newURL = store.renameSelected(to: renameText) else {
                        return
                    }
                    if let openPath = editor.fileURL?.path {
                        if openPath == oldPath {
                            editor.relocate(to: newURL)
                        } else if openPath.hasPrefix(oldPath + "/") {
                            let suffix = String(openPath.dropFirst(oldPath.count))
                            let relocated = URL(fileURLWithPath: newURL.path + suffix)
                            editor.relocate(to: relocated)
                        }
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
        // Deselection only — close the note.
        guard let newValue else {
            if !editor.close() {
                if let path = editor.fileURL?.path {
                    store.selection = path
                }
                flushEditorError()
            }
            return
        }

        guard let root = store.rootNode,
              let node = FileSystemVault.findNode(id: newValue, in: root) else {
            return
        }

        // Folder selection: leave the open note alone (sidebar navigation only).
        if node.isDirectory {
            return
        }

        if editor.fileURL?.path != node.url.path {
            let previousPath = editor.fileURL?.path
            if editor.open(url: node.url) {
                flushEditorError()
            } else {
                // Save failed or external conflict — stay on the dirty note.
                store.selection = previousPath
                flushEditorError()
            }
        }
    }

    private func flushEditorError() {
        // External conflicts / missing file use their own dialogs.
        guard !editor.hasExternalConflict, !editor.hasMissingFile else { return }
        guard let last = editor.lastError else { return }
        store.present(error: last.error, context: last.context)
        editor.lastError = nil
    }

    private func openWikiLink(_ text: String) {
        guard let url = store.resolveWikiLink(text) else { return }
        guard editor.saveIfNeeded() else {
            flushEditorError()
            return
        }
        store.selection = url.path
        if !editor.open(url: url) {
            flushEditorError()
        }
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
