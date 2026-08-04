import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    /// When this window already has a vault, Open Vault can spawn another window first.
    var openNewVaultWindow: (() -> Void)?
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

    @State private var hostWindowNumber: Int?

    var body: some View {
        rootShell
            .frame(minWidth: 900, minHeight: 560)
            .font(LyraFonts.body)
            .background(
                WindowNumberReader { hostWindowNumber = $0 }
            )
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
            .modifier(ContentViewChrome(
                store: store,
                editor: editor,
                renameTarget: $renameTarget,
                showDeleteConfirm: $showDeleteConfirm,
                onSelectionChange: handleSelectionChange,
                onHasErrorChange: handleHasErrorChange,
                flushEditorError: flushEditorError,
                exportPDF: exportPDF,
                openVault: openVault,
                toggleViewMode: { noteViewMode = noteViewMode.next() },
                renameSheet: renameSheet,
                shouldHandleCommands: {
                    guard let hostWindowNumber else { return true }
                    return NSApp.keyWindow?.windowNumber == hostWindowNumber
                }
            ))
    }

    @ViewBuilder
    private var rootShell: some View {
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

    private var vaultWorkspace: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                renameTarget: $renameTarget,
                showDeleteConfirm: $showDeleteConfirm,
                onExportNotePDF: exportNotePDF,
                onExportFolderSeparate: exportFolderSeparatePDFs,
                onExportFolderCombined: exportFolderCombinedPDF
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        store.createNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            noteDetail
                .toolbar {
                    ToolbarItemGroup {
                        detailToolbar
                    }
                }
        }
    }

    @ViewBuilder
    private var detailToolbar: some View {
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
        .help("Source or Reading (⌘E)")

        Button {
            exportPDF()
        } label: {
            Label("Export PDF", systemImage: "doc.richtext")
        }
        .disabled(editor.fileURL == nil)
        .help("Export current note to PDF")

        saveStatusLabel
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
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

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            if store.rootURL != nil {
                store.refresh()
            }
        } else {
            _ = editor.saveIfNeeded()
            flushEditorError()
        }
    }

    private func handleHasErrorChange(_ has: Bool) {
        // Surface autosave failures once; the toolbar indicator covers the ongoing state.
        if has && !didAlertSaveFailure {
            didAlertSaveFailure = true
            flushEditorError()
        }
        if !has {
            didAlertSaveFailure = false
        }
    }

    private func openVault() {
        guard let url = VaultFolderPicker.pick(message: "Choose a folder to use as a Lyra vault") else {
            return
        }
        if store.rootURL == nil {
            store.openVault(at: url)
            return
        }
        // Already have a vault — open the chosen folder in a new window.
        AppSession.shared.setPendingVaultURL(url)
        openNewVaultWindow?()
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
        guard let noteURL = editor.fileURL else { return }
        _ = editor.saveIfNeeded()
        flushEditorError()
        exportMarkdown(
            editor.text,
            noteDirectory: noteURL.deletingLastPathComponent(),
            suggestedName: noteURL.deletingPathExtension().lastPathComponent + ".pdf",
            directoryURL: noteURL.deletingLastPathComponent()
        )
    }

    private func exportNotePDF(_ node: VaultNode) {
        guard !node.isDirectory, store.rootURL != nil else { return }
        let markdown: String
        if editor.fileURL?.path == node.url.path {
            _ = editor.saveIfNeeded()
            markdown = editor.text
        } else {
            do {
                markdown = try String(contentsOf: node.url, encoding: .utf8)
            } catch {
                store.present(error: error, context: .exportPDF)
                return
            }
        }
        exportMarkdown(
            markdown,
            noteDirectory: node.url.deletingLastPathComponent(),
            suggestedName: node.url.deletingPathExtension().lastPathComponent + ".pdf",
            directoryURL: node.url.deletingLastPathComponent()
        )
    }

    private func exportFolderSeparatePDFs(_ folder: VaultNode) {
        guard folder.isDirectory, let vault = store.rootURL else { return }
        let notes = FileSystemVault.collectNoteURLs(from: folder)
        guard !notes.isEmpty else {
            store.present(context: .exportPDF, message: "This folder has no Markdown notes to export.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for \(notes.count) PDF file(s)."
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            var failures = 0
            for noteURL in notes {
                do {
                    let md = try String(contentsOf: noteURL, encoding: .utf8)
                    let data = try NotePDFExporter.pdfData(
                        markdown: md,
                        noteDirectory: noteURL.deletingLastPathComponent(),
                        vaultRoot: vault
                    )
                    let base = noteURL.deletingPathExtension().lastPathComponent
                    var out = dest.appendingPathComponent("\(base).pdf")
                    var n = 2
                    while FileManager.default.fileExists(atPath: out.path) {
                        out = dest.appendingPathComponent("\(base)-\(n).pdf")
                        n += 1
                    }
                    try data.write(to: out, options: .atomic)
                } catch {
                    failures += 1
                }
            }
            if failures > 0 {
                store.present(
                    context: .exportPDF,
                    message: "Exported with \(failures) failure(s). Check permissions and disk space."
                )
            }
        }
    }

    private func exportFolderCombinedPDF(_ folder: VaultNode) {
        guard folder.isDirectory, let vault = store.rootURL else { return }
        let notes = FileSystemVault.collectNoteURLs(from: folder).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        guard !notes.isEmpty else {
            store.present(context: .exportPDF, message: "This folder has no Markdown notes to export.")
            return
        }
        do {
            var sources: [NotePDFExporter.NoteSource] = []
            for noteURL in notes {
                let md = try String(contentsOf: noteURL, encoding: .utf8)
                sources.append(
                    NotePDFExporter.NoteSource(
                        title: noteURL.deletingPathExtension().lastPathComponent,
                        markdown: md,
                        noteDirectory: noteURL.deletingLastPathComponent()
                    )
                )
            }
            let data = try NotePDFExporter.pdfData(notes: sources, vaultRoot: vault)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = folder.name + ".pdf"
            panel.directoryURL = folder.url
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

    private func exportMarkdown(
        _ markdown: String,
        noteDirectory: URL,
        suggestedName: String,
        directoryURL: URL?
    ) {
        guard let vault = store.rootURL else { return }
        do {
            let data = try NotePDFExporter.pdfData(
                markdown: markdown,
                noteDirectory: noteDirectory,
                vaultRoot: vault
            )
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = suggestedName
            panel.directoryURL = directoryURL
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

// MARK: - Key-window tracking for multi-window menus

private struct WindowNumberReader: NSViewRepresentable {
    var onChange: (Int?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window?.windowNumber) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window?.windowNumber) }
    }
}

// MARK: - Chrome (dialogs + commands) — kept out of `body` so the type-checker stays happy

private struct ContentViewChrome: ViewModifier {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @Binding var renameTarget: VaultNode?
    @Binding var showDeleteConfirm: Bool
    var onSelectionChange: (VaultNode.ID?) -> Void
    var onHasErrorChange: (Bool) -> Void
    var flushEditorError: () -> Void
    var exportPDF: () -> Void
    var openVault: () -> Void
    var toggleViewMode: () -> Void
    var renameSheet: (VaultNode) -> AnyView
    var shouldHandleCommands: () -> Bool

    init(
        store: VaultStore,
        editor: EditorViewModel,
        renameTarget: Binding<VaultNode?>,
        showDeleteConfirm: Binding<Bool>,
        onSelectionChange: @escaping (VaultNode.ID?) -> Void,
        onHasErrorChange: @escaping (Bool) -> Void,
        flushEditorError: @escaping () -> Void,
        exportPDF: @escaping () -> Void,
        openVault: @escaping () -> Void,
        toggleViewMode: @escaping () -> Void,
        renameSheet: @escaping (VaultNode) -> some View,
        shouldHandleCommands: @escaping () -> Bool
    ) {
        self.store = store
        self.editor = editor
        self._renameTarget = renameTarget
        self._showDeleteConfirm = showDeleteConfirm
        self.onSelectionChange = onSelectionChange
        self.onHasErrorChange = onHasErrorChange
        self.flushEditorError = flushEditorError
        self.exportPDF = exportPDF
        self.openVault = openVault
        self.toggleViewMode = toggleViewMode
        self.renameSheet = { AnyView(renameSheet($0)) }
        self.shouldHandleCommands = shouldHandleCommands
    }

    func body(content: Content) -> some View {
        content
            .modifier(ContentViewDialogs(
                store: store,
                editor: editor,
                renameTarget: $renameTarget,
                showDeleteConfirm: $showDeleteConfirm,
                flushEditorError: flushEditorError,
                renameSheet: renameSheet
            ))
            .onChange(of: store.selection) { _, newValue in
                onSelectionChange(newValue)
            }
            .onChange(of: editor.hasError) { _, has in
                onHasErrorChange(has)
            }
            .modifier(ContentViewCommands(
                shouldHandle: shouldHandleCommands,
                exportPDF: exportPDF,
                openVault: openVault,
                toggleViewMode: toggleViewMode,
                createNote: { store.createNote() },
                createFolder: { store.createFolder() },
                refresh: { store.refresh() },
                save: {
                    _ = editor.saveIfNeeded()
                    flushEditorError()
                },
                quitSaveFailed: flushEditorError
            ))
    }
}

private struct ContentViewDialogs: ViewModifier {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @Binding var renameTarget: VaultNode?
    @Binding var showDeleteConfirm: Bool
    var flushEditorError: () -> Void
    var renameSheet: (VaultNode) -> AnyView

    func body(content: Content) -> some View {
        content
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
                    if !editor.saveIfNeeded(force: true) {
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
                    _ = editor.close()
                    store.selection = nil
                }
                Button("Cancel", role: .cancel) {
                    editor.hasMissingFile = false
                    editor.deferConflict()
                }
            } message: {
                Text("This note was moved or deleted outside Lyra. Save a copy at the old path, or close the note.")
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
    }
}

private struct ContentViewCommands: ViewModifier {
    var shouldHandle: () -> Bool
    var exportPDF: () -> Void
    var openVault: () -> Void
    var toggleViewMode: () -> Void
    var createNote: () -> Void
    var createFolder: () -> Void
    var refresh: () -> Void
    var save: () -> Void
    var quitSaveFailed: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .lyraSaveNote)) { _ in
                guard shouldHandle() else { return }
                save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraExportPDF)) { _ in
                guard shouldHandle() else { return }
                exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraNewNote)) { _ in
                guard shouldHandle() else { return }
                createNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraNewFolder)) { _ in
                guard shouldHandle() else { return }
                createFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraOpenVault)) { _ in
                guard shouldHandle() else { return }
                openVault()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraToggleViewMode)) { _ in
                guard shouldHandle() else { return }
                toggleViewMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraRefreshVault)) { _ in
                guard shouldHandle() else { return }
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraQuitSaveFailed)) { _ in
                // All windows may surface; only key window needs UI (others already saved or clean).
                guard shouldHandle() else { return }
                quitSaveFailed()
            }
    }
}
