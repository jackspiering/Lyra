import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: VaultStore
    @Bindable var tabs: NoteTabController
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

    /// Active tab’s editor (always exists — controller keeps ≥1 tab).
    private var editor: EditorViewModel {
        tabs.selectedEditor
    }

    @State private var hostWindowNumber: Int?

    var body: some View {
        rootShell
            // Empty chrome title — vault name must not repeat in toolbar principal.
            .navigationTitle("")
            .frame(minWidth: 900, minHeight: 560)
            .font(LyraFonts.body)
            .background(
                WindowNumberReader { hostWindowNumber = $0 }
            )
            .background(
                DocumentEditedReader(isEdited: tabs.anyDirty)
            )
            .background(
                WindowCloseGuard(
                    editors: tabs.allEditors(),
                    onSaveFailure: handleEditorSaveFailures
                )
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
                quitSaveFailed: handleEditorSaveFailures,
                openVault: openVault,
                goToFile: goToFile,
                beginNewNote: beginNewNote,
                requestDelete: requestDelete,
                toggleViewMode: { noteViewMode = noteViewMode.next() },
                focusVaultSearch: { vaultSearchFocusToken += 1 },
                newTab: newTab,
                openInNewTab: openSelectionInNewTab,
                closeTab: { closeTab(id: tabs.selectedTabID) },
                newNoteSheet: newNoteSheet,
                deleteConfirmSheet: deleteConfirmSheet,
                shouldHandleCommands: {
                    guard let hostWindowNumber else { return false }
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
        VStack(spacing: 0) {
            NoteTabBar(
                tabs: tabs,
                onNewTab: newTab,
                onCloseTab: { closeTab(id: $0) },
                onSelectTab: selectTab
            )
            tabDetailBody
        }
    }

    @ViewBuilder
    private var tabDetailBody: some View {
        if editor.fileURL == nil {
            EmptyTabView(
                onNewNote: beginNewNote,
                onGoToFile: goToFile,
                onCloseTab: { closeTab(id: tabs.selectedTabID) }
            )
        } else {
            VStack(spacing: 0) {
                NoteTitleBar(
                    title: NoteTitle.displayTitle(markdown: editor.text, fileURL: editor.fileURL),
                    onCommit: commitNoteTitle
                )
                .id(editor.fileURL?.path)
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
                text: Binding(
                    get: { editor.text },
                    set: { editor.text = $0 }
                ),
                vaultRoot: store.rootURL,
                noteURL: editor.fileURL,
                onEdit: { editor.noteEdited() },
                onPasteError: { store.present(context: .pasteImage, message: $0) }
            )
            // Per-file identity: reset selection, scroll, and undo when switching notes/tabs.
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

    // MARK: - Tabs

    private func newTab() {
        guard store.rootURL != nil else { return }
        let tab = tabs.newEmptyTab()
        AppSession.shared.register(editor: tab.editor, store: store)
        // Clear sidebar so re-clicking the same note opens it in this empty tab.
        store.selection = nil
    }

    private func selectTab(_ id: NoteTab.ID) {
        tabs.select(id)
        // Sync sidebar highlight to the note in this tab; clear when empty so re-click re-opens.
        if let path = tabs.selectedTab?.editor.fileURL?.path {
            store.selection = path
        } else {
            store.selection = nil
        }
    }

    private func closeTab(id: NoteTab.ID?) {
        guard let id else { return }
        guard let tab = tabs.tabs.first(where: { $0.id == id }) else { return }
        let editorRef = tab.editor
        if tabs.close(id: id) {
            // Unregister only when the tab was removed (not last-tab → empty).
            if !tabs.tabs.contains(where: { $0.id == id }) {
                AppSession.shared.unregister(editor: editorRef)
            }
            // After close, align sidebar to remaining note or clear for empty tab.
            if let path = tabs.selectedTab?.editor.fileURL?.path {
                store.selection = path
            } else {
                store.selection = nil
            }
        } else {
            // Flush the tab that failed to save, not necessarily the previously selected editor.
            selectTab(containing: editorRef)
            flushEditorError(for: editorRef)
        }
    }

    // MARK: - Lifecycle / vault

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            if store.rootURL != nil {
                store.refresh()
            }
        } else {
            let failures = tabs.tabs.compactMap { tab in
                tab.editor.saveIfNeeded() ? nil : tab.editor
            }
            handleEditorSaveFailures(failures)
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

    /// Empty-tab “Go to file” / ⌘O when a vault is open: pick a Markdown note and open it.
    private func goToFile() {
        guard let root = store.rootURL else {
            openVault()
            return
        }
        guard let url = VaultNotePicker.pick(vaultRoot: root) else { return }
        store.selection = url.path
        activateNote(url: url)
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
        guard let node = store.selectedNode() else { return }
        // Flush + empty any tab that has this note (or a note under a deleted folder) open.
        // Do not rely on selection=nil to close editors — that would close the wrong tab.
        let path = node.url.path
        for tab in tabs.tabs {
            guard let openPath = tab.editor.fileURL?.path else { continue }
            let affected = openPath == path || (node.isDirectory && openPath.hasPrefix(path + "/"))
            guard affected else { continue }
            if !tab.editor.close() {
                flushEditorError(for: tab.editor)
                return
            }
        }
        store.deleteSelected()
        // deleteSelected nils selection; re-sync sidebar to whatever note (if any) is still active.
        // handleSelectionChange ignores nil and selectOpenNote avoids re-open/dual-open.
        if let path = tabs.selectedTab?.editor.fileURL?.path {
            store.selection = path
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

    /// Sidebar inline rename: flush editors, rename on disk, relocate open notes if needed.
    private func commitSidebarRename(node: VaultNode, newName: String) -> Bool {
        let oldPath = node.url.path
        for tab in tabs.tabs {
            guard tab.editor.saveIfNeeded() else {
                flushEditorError(for: tab.editor)
                return false
            }
        }
        store.selection = node.id
        guard let newURL = store.renameSelected(to: newName) else {
            return false
        }
        tabs.relocateOpenNotes(oldPath: oldPath, newURL: newURL)
        return true
    }

    /// Title field commit: sync leading H1 when present; otherwise rename the file stem.
    private func commitNoteTitle(_ newTitle: String) {
        guard editor.fileURL != nil else { return }
        let result = NoteTitle.applyingTitle(newTitle, to: editor.text)
        if result.markdown != editor.text {
            editor.text = result.markdown
            editor.noteEdited()
        }
        guard let stem = result.renamedStem, let url = editor.fileURL else { return }
        let currentStem = url.deletingPathExtension().lastPathComponent
        guard stem != currentStem else { return }
        // Flush this note (and siblings) before the path changes.
        for tab in tabs.tabs {
            guard tab.editor.saveIfNeeded() else {
                flushEditorError(for: tab.editor)
                return
            }
        }
        let oldPath = url.path
        store.selection = oldPath
        guard let newURL = store.renameSelected(to: stem + ".md") else { return }
        tabs.relocateOpenNotes(oldPath: oldPath, newURL: newURL)
    }

    private func handleSelectionChange(_ newValue: VaultNode.ID?) {
        // Multi-tab: nil selection is not “close editor” (mirrors folder select).
        // Delete already empties tabs that held the deleted path; empty-tab / new-tab clear selection intentionally.
        guard let newValue else { return }

        guard let root = store.rootNode,
              let node = FileSystemVault.findNode(id: newValue, in: root) else {
            return
        }

        // Folder selection: leave the open note alone (sidebar navigation only).
        if node.isDirectory {
            return
        }

        activateNote(url: node.url)
    }

    /// Open a note from sidebar / wiki: already open → select; empty active → fill; else new tab.
    private func activateNote(url: URL) {
        if tabs.selectOpenNote(path: url.path) { return }
        if editor.fileURL == nil {
            // empty active tab — fill it
            _ = tabs.openInActiveTab(url: url) { created in
                AppSession.shared.register(editor: created.editor, store: store)
            }
            // Whether the fill succeeded or not, surface any failure from the previous save/open.
            flushEditorError()
            return
        }
        if editor.fileURL?.path == url.path { return }
        // Active has another note → new tab
        let ok = tabs.openInNewTab(
            url: url,
            onCreated: { created in
                AppSession.shared.register(editor: created.editor, store: store)
            },
            onFailed: { failed in
                flushEditorError(for: failed)
            }
        )
        if ok {
            flushEditorError()
        } else {
            // Restored previous tab after rollback — align sidebar to it.
            store.selection = tabs.selectedTab?.editor.fileURL?.path
        }
    }

    /// File → Open in New Tab: always new tab if not already open; if already open, just select.
    private func openSelectionInNewTab() {
        guard let url = store.selectedFileURL() else { return }
        if tabs.selectOpenNote(path: url.path) {
            store.selection = url.path
            return
        }
        let ok = tabs.openInNewTab(
            url: url,
            onCreated: { created in
                AppSession.shared.register(editor: created.editor, store: store)
            },
            onFailed: { failed in
                flushEditorError(for: failed)
            }
        )
        if ok {
            flushEditorError()
        }
        // On failure, selection stays on the chosen file; failed editor error already flushed via onFailed.
    }

    private func flushEditorError() {
        flushEditorError(for: editor)
    }

    private func flushEditorError(for ed: EditorViewModel) {
        // External conflicts / missing file use their own dialogs.
        guard !ed.hasExternalConflict, !ed.hasMissingFile else { return }
        guard let last = ed.lastError else { return }
        store.present(error: last.error, context: last.context)
        ed.lastError = nil
    }

    /// Select the tab that owns a failed editor so conflict/missing-file
    /// dialogs and ordinary save alerts are attached to the right note.
    private func handleEditorSaveFailures(_ failures: [EditorViewModel]) {
        guard let failed = failures.first(where: { editor in
            tabs.tabs.contains { $0.editor === editor }
        }) else { return }
        selectTab(containing: failed)
        flushEditorError(for: failed)
    }

    private func selectTab(containing editor: EditorViewModel) {
        guard let tab = tabs.tabs.first(where: { $0.editor === editor }) else { return }
        tabs.select(tab.id)
        store.selection = tab.editor.fileURL?.path
    }

    private func openWikiLink(_ text: String) {
        guard let url = store.resolveWikiLink(text) else { return }
        // activateNote / selectOpenNote open or switch tabs; still flush dirty active first when replacing.
        if tabs.selectOpenNote(path: url.path) {
            store.selection = url.path
            return
        }
        guard editor.saveIfNeeded() else {
            flushEditorError()
            return
        }
        store.selection = url.path
        activateNote(url: url)
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
        if let openTab = tabs.tabs.first(where: { $0.editor.fileURL?.path == node.url.path }) {
            _ = openTab.editor.saveIfNeeded()
            markdown = openTab.editor.text
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
        let liveBuffers = exportBufferSnapshot()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for \(notes.count) PDF file(s)."
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            Task { @MainActor in
                let failures = await Task.detached(priority: .userInitiated) {
                    var failures = 0
                    for noteURL in notes {
                        do {
                            let markdown: String
                            if let live = liveBuffers[noteURL.path] {
                                markdown = live
                            } else {
                                markdown = try String(contentsOf: noteURL, encoding: .utf8)
                            }
                            let data = try NotePDFExporter.pdfData(
                                markdown: markdown,
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
                    return failures
                }.value
                if failures > 0 {
                    store.present(
                        context: .exportPDF,
                        message: "Exported with \(failures) failure(s). Check permissions and disk space."
                    )
                }
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
        let liveBuffers = exportBufferSnapshot()
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    var sources: [NotePDFExporter.NoteSource] = []
                    for noteURL in notes {
                        let markdown: String
                        if let live = liveBuffers[noteURL.path] {
                            markdown = live
                        } else {
                            markdown = try String(contentsOf: noteURL, encoding: .utf8)
                        }
                        sources.append(
                            NotePDFExporter.NoteSource(
                                title: noteURL.deletingPathExtension().lastPathComponent,
                                markdown: markdown,
                                noteDirectory: noteURL.deletingLastPathComponent()
                            )
                        )
                    }
                    return try NotePDFExporter.pdfData(notes: sources, vaultRoot: vault)
                }.value
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
    }

    private func exportMarkdown(
        _ markdown: String,
        noteDirectory: URL,
        suggestedName: String,
        directoryURL: URL?
    ) {
        guard let vault = store.rootURL else { return }
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try NotePDFExporter.pdfData(
                        markdown: markdown,
                        noteDirectory: noteDirectory,
                        vaultRoot: vault
                    )
                }.value
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

    private func exportBufferSnapshot() -> [String: String] {
        var buffers: [String: String] = [:]
        for tab in tabs.tabs {
            guard let path = tab.editor.fileURL?.path else { continue }
            _ = tab.editor.saveIfNeeded()
            flushEditorError(for: tab.editor)
            buffers[path] = tab.editor.text
        }
        return buffers
    }

}
