import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    /// When this window already has a vault, Open Vault can spawn another window first.
    var openNewVaultWindow: (() -> Void)?
    @AppStorage("lyra.noteViewMode") private var noteViewModeRaw = NoteViewMode.source.rawValue
    @State private var showDeleteConfirm = false
    @State private var deleteDontAskAgain = false
    @State private var showNewNoteSheet = false
    @State private var newNoteName = ""
    @State private var didAlertSaveFailure = false
    /// Bumped when ⌘F / Find in Vault targets this window so the sidebar focuses search.
    @State private var vaultSearchFocusToken = 0
    @Environment(\.scenePhase) private var scenePhase

    private var noteViewMode: NoteViewMode {
        get { NoteViewMode(rawValue: noteViewModeRaw) ?? .source }
        nonmutating set { noteViewModeRaw = newValue.rawValue }
    }

    @State private var hostWindowNumber: Int?

    var body: some View {
        rootShell
            // Vault folder name when open; empty when none — no center “Lyra” brand.
            .navigationTitle(store.rootURL?.lastPathComponent ?? "")
            .frame(minWidth: 900, minHeight: 560)
            .font(LyraFonts.body)
            .background(
                WindowNumberReader { hostWindowNumber = $0 }
            )
            .background(
                DocumentEditedReader(isEdited: editor.isDirty)
            )
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
            .modifier(ContentViewChrome(
                store: store,
                editor: editor,
                showDeleteConfirm: $showDeleteConfirm,
                showNewNoteSheet: $showNewNoteSheet,
                onSelectionChange: handleSelectionChange,
                onHasErrorChange: handleHasErrorChange,
                flushEditorError: flushEditorError,
                exportPDF: exportPDF,
                openVault: openVault,
                beginNewNote: beginNewNote,
                requestDelete: requestDelete,
                toggleViewMode: { noteViewMode = noteViewMode.next() },
                focusVaultSearch: { vaultSearchFocusToken += 1 },
                newNoteSheet: newNoteSheet,
                deleteConfirmSheet: deleteConfirmSheet,
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
                onCommitRename: commitSidebarRename,
                onRequestDelete: requestDelete,
                onNewNote: beginNewNote,
                onExportNotePDF: exportNotePDF,
                onExportFolderSeparate: exportFolderSeparatePDFs,
                onExportFolderCombined: exportFolderCombinedPDF,
                searchFocusToken: vaultSearchFocusToken
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        openVault()
                    } label: {
                        Label("Open Vault", systemImage: "folder")
                    }
                    .help("Open Vault…")

                    Button {
                        beginNewNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .help("New Note")
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
        // Open Vault stays in the sidebar toolbar and File menu only.

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
        }
        // Dirty state: traffic-light close button via DocumentEditedReader (no grey Unsaved label).
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
            VStack(spacing: 0) {
                noteContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                EditorStatusBar(
                    wordCount: NoteStats.wordCount(editor.text),
                    characterCount: NoteStats.characterCount(editor.text),
                    created: editor.createdAt,
                    lastSaved: editor.lastSavedAt
                )
            }
        }
    }

    @ViewBuilder
    private var noteContent: some View {
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

    private func beginNewNote() {
        guard store.rootURL != nil else { return }
        if GeneralPreferences.promptForNewNoteName {
            let stem = GeneralPreferences.defaultNoteStem
            newNoteName = "\(stem).md"
            showNewNoteSheet = true
        } else {
            store.createNote(named: nil)
        }
    }

    /// ⌘⌫, File → Move to Trash, or context Delete. Respects note vs folder confirm prefs.
    private func requestDelete() {
        guard let node = store.selectedNode() else { return }
        let needsConfirm = node.isDirectory
            ? GeneralPreferences.confirmDeleteFolder
            : GeneralPreferences.confirmDeleteNote
        if needsConfirm {
            deleteDontAskAgain = false
            showDeleteConfirm = true
        } else {
            performDelete()
        }
    }

    private func performDelete() {
        if editor.close() {
            store.deleteSelected()
        } else {
            flushEditorError()
        }
    }

    private func deleteConfirmSheet() -> some View {
        let node = store.selectedNode()
        let name = node?.name ?? "this item"
        let isFolder = node?.isDirectory == true
        return VStack(alignment: .leading, spacing: 16) {
            Text("Move to Trash").font(LyraFonts.headline)
            Text("Move “\(name)” to the Trash?")
            Toggle("Don’t ask again", isOn: $deleteDontAskAgain)
            HStack {
                Spacer()
                Button("Cancel") { showDeleteConfirm = false }
                Button("Move to Trash", role: .destructive) {
                    if deleteDontAskAgain {
                        let key = isFolder
                            ? GeneralPreferences.confirmDeleteFolderKey
                            : GeneralPreferences.confirmDeleteNoteKey
                        UserDefaults.standard.set(false, forKey: key)
                    }
                    showDeleteConfirm = false
                    performDelete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var newNoteNameIsValid: Bool {
        if case .ok = FilenameValidation.validate(newNoteName, isDirectory: false) {
            return true
        }
        return false
    }

    private func newNoteSheet() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Note").font(LyraFonts.headline)
            NewNoteNameField(text: $newNoteName, onSubmit: submitNewNote)
            HStack {
                Spacer()
                Button("Cancel") { showNewNoteSheet = false }
                Button("Create", action: submitNewNote)
                .keyboardShortcut(.defaultAction)
                .disabled(!newNoteNameIsValid)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func submitNewNote() {
        guard newNoteNameIsValid else { return }
        if store.createNote(named: newNoteName) {
            showNewNoteSheet = false
        }
    }

    /// Sidebar inline rename: flush editor, rename on disk, relocate open note if needed.
    private func commitSidebarRename(node: VaultNode, newName: String) -> Bool {
        let oldPath = node.url.path
        guard editor.saveIfNeeded() else {
            flushEditorError()
            return false
        }
        store.selection = node.id
        guard let newURL = store.renameSelected(to: newName) else {
            return false
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
        return true
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

// MARK: - Standard macOS dirty state on the close button

private struct DocumentEditedReader: NSViewRepresentable {
    var isEdited: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.isDocumentEdited = isEdited
    }
}

// MARK: - New-note name field (selects stem before `.md` on first focus)

private struct NewNoteNameField: NSViewRepresentable {
    @Binding var text: String
    /// Called on Return while the field is focused (Create default action may not fire then).
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "Name"
        field.delegate = context.coordinator
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        DispatchQueue.main.async {
            selectStem(in: field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func selectStem(in field: NSTextField) {
        field.window?.makeFirstResponder(field)
        let value = field.stringValue as NSString
        let length = value.length
        if (value as String).lowercased().hasSuffix(".md"), length > 3 {
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: length - 3)
        } else {
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NewNoteNameField

        init(_ parent: NewNoteNameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Return while focused → Create (SwiftUI `.defaultAction` often does not fire for NSTextField).
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Chrome (dialogs + commands) — kept out of `body` so the type-checker stays happy

private struct ContentViewChrome: ViewModifier {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @Binding var showDeleteConfirm: Bool
    @Binding var showNewNoteSheet: Bool
    var onSelectionChange: (VaultNode.ID?) -> Void
    var onHasErrorChange: (Bool) -> Void
    var flushEditorError: () -> Void
    var exportPDF: () -> Void
    var openVault: () -> Void
    var beginNewNote: () -> Void
    var requestDelete: () -> Void
    var toggleViewMode: () -> Void
    var focusVaultSearch: () -> Void
    var newNoteSheet: () -> AnyView
    var deleteConfirmSheet: () -> AnyView
    var shouldHandleCommands: () -> Bool

    init(
        store: VaultStore,
        editor: EditorViewModel,
        showDeleteConfirm: Binding<Bool>,
        showNewNoteSheet: Binding<Bool>,
        onSelectionChange: @escaping (VaultNode.ID?) -> Void,
        onHasErrorChange: @escaping (Bool) -> Void,
        flushEditorError: @escaping () -> Void,
        exportPDF: @escaping () -> Void,
        openVault: @escaping () -> Void,
        beginNewNote: @escaping () -> Void,
        requestDelete: @escaping () -> Void,
        toggleViewMode: @escaping () -> Void,
        focusVaultSearch: @escaping () -> Void,
        newNoteSheet: @escaping () -> some View,
        deleteConfirmSheet: @escaping () -> some View,
        shouldHandleCommands: @escaping () -> Bool
    ) {
        self.store = store
        self.editor = editor
        self._showDeleteConfirm = showDeleteConfirm
        self._showNewNoteSheet = showNewNoteSheet
        self.onSelectionChange = onSelectionChange
        self.onHasErrorChange = onHasErrorChange
        self.flushEditorError = flushEditorError
        self.exportPDF = exportPDF
        self.openVault = openVault
        self.beginNewNote = beginNewNote
        self.requestDelete = requestDelete
        self.toggleViewMode = toggleViewMode
        self.focusVaultSearch = focusVaultSearch
        self.newNoteSheet = { AnyView(newNoteSheet()) }
        self.deleteConfirmSheet = { AnyView(deleteConfirmSheet()) }
        self.shouldHandleCommands = shouldHandleCommands
    }

    func body(content: Content) -> some View {
        content
            .modifier(ContentViewDialogs(
                store: store,
                editor: editor,
                showDeleteConfirm: $showDeleteConfirm,
                showNewNoteSheet: $showNewNoteSheet,
                flushEditorError: flushEditorError,
                newNoteSheet: newNoteSheet,
                deleteConfirmSheet: deleteConfirmSheet
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
                createNote: beginNewNote,
                createFolder: { store.createFolder() },
                requestDelete: requestDelete,
                refresh: { store.refresh() },
                save: {
                    _ = editor.saveIfNeeded()
                    flushEditorError()
                },
                quitSaveFailed: flushEditorError,
                focusVaultSearch: focusVaultSearch
            ))
    }
}

private struct ContentViewDialogs: ViewModifier {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @Binding var showDeleteConfirm: Bool
    @Binding var showNewNoteSheet: Bool
    var flushEditorError: () -> Void
    var newNoteSheet: () -> AnyView
    var deleteConfirmSheet: () -> AnyView

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
            .sheet(isPresented: $showNewNoteSheet) {
                newNoteSheet()
            }
            .sheet(isPresented: $showDeleteConfirm) {
                deleteConfirmSheet()
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
    var requestDelete: () -> Void
    var refresh: () -> Void
    var save: () -> Void
    var quitSaveFailed: () -> Void
    var focusVaultSearch: () -> Void

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
            .onReceive(NotificationCenter.default.publisher(for: .lyraDeleteSelection)) { _ in
                guard shouldHandle() else { return }
                requestDelete()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraFocusVaultSearch)) { _ in
                guard shouldHandle() else { return }
                focusVaultSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraQuitSaveFailed)) { _ in
                // All windows may surface; only key window needs UI (others already saved or clean).
                guard shouldHandle() else { return }
                quitSaveFailed()
            }
    }
}
