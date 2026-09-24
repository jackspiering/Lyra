import AppKit
import SwiftUI

/// A note rename that left `[[links]]` in other notes pointing at the old name.
struct PendingLinkUpdate: Identifiable {
    let id = UUID()
    let oldURL: URL
    let newStem: String
    let sources: [Backlink]
    /// Resolver from before the rename, which still resolves the old name.
    let resolver: WikiLinkResolver
}

/// Inputs that invalidate the backlinks list.
private struct BacklinksKey: Equatable {
    var path: String?
    var text: String
    var indexVersion: Int
}

struct ContentView: View {
    @Bindable var store: VaultStore
    @Bindable var tabs: NoteTabController
    /// When this window already has a vault, Open Vault can spawn another window first.
    /// The UUID is the handoff token for the folder that window should open.
    var openNewVaultWindow: ((UUID) -> Void)?
    @AppStorage("lyra.noteViewMode") private var noteViewModeRaw = NoteViewMode.source.rawValue
    @State private var backlinkItems: [Backlink] = []
    @State private var backlinksPath: String?
    @State private var pendingLinkUpdate: PendingLinkUpdate?
    @State private var showDeleteConfirm = false
    @State private var deleteDontAskAgain = false
    @State private var showNewNoteSheet = false
    @State private var newNoteName = ""
    @State private var didAlertSaveFailure = false
    @State private var didAlertBackgroundSaveFailure = false
    /// Bumped when ⌘F should show the Source find bar.
    @State private var findBarToken = 0
    @State private var wikiFlow: WikiFlow
    @State private var pdfExport: PDFExportFlow
    @State private var showVaultSearch = false
    @State private var vaultSearchQuery = ""
    @SceneStorage("lyra.showBacklinks") private var showBacklinks = false
    @Environment(\.scenePhase) private var scenePhase

    private var noteViewMode: NoteViewMode {
        get { NoteViewMode(rawValue: noteViewModeRaw) ?? .source }
        nonmutating set { noteViewModeRaw = newValue.rawValue }
    }

    /// Active tab’s editor (always exists — controller keeps ≥1 tab).
    private var editor: EditorViewModel {
        tabs.selectedEditor
    }

    init(
        store: VaultStore,
        tabs: NoteTabController,
        openNewVaultWindow: ((UUID) -> Void)?
    ) {
        self.store = store
        self.tabs = tabs
        self.openNewVaultWindow = openNewVaultWindow
        // One presentation policy shared by both flows.
        let flushError: (EditorViewModel) -> Void = {
            Self.flushEditorError($0, presentingOn: store)
        }
        _wikiFlow = State(initialValue: WikiFlow(store: store, tabs: tabs, flushError: flushError))
        _pdfExport = State(initialValue: PDFExportFlow(store: store, tabs: tabs, flushError: flushError))
    }

    var body: some View {
        rootShell
            // Empty chrome title — vault name must not repeat in toolbar principal.
            .navigationTitle("")
            // Toolbar and title bar sit on the same chrome tone as the tab strip.
            .containerBackground(LyraTheme.chromeColor, for: .window)
            .frame(minWidth: 900, minHeight: 560)
            .font(LyraFonts.body)
            .background(
                DocumentEditedReader(isEdited: tabs.anyDirty)
            )
            .background(
                WindowCloseGuard(
                    editors: tabs.allEditors(),
                    onSaveFailure: handleEditorSaveFailures
                )
            )
            .onChange(of: tabs.tabs.map { $0.editor.hasError }) { _, _ in
                handleBackgroundSaveFailure()
            }
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
                flushEditorError: { Self.flushEditorError(editor, presentingOn: store) },
                quitSaveFailed: handleEditorSaveFailures,
                newNoteSheet: newNoteSheet,
                deleteConfirmSheet: deleteConfirmSheet
            ))
            // Menu commands ride the focused scene: the key vault window
            // publishes its command set; unfocused windows stay inert.
            .focusedSceneValue(\.vaultCommands, VaultCommands(
                save: {
                    _ = editor.saveIfNeeded()
                    Self.flushEditorError(editor, presentingOn: store)
                },
                exportPDF: { pdfExport.exportActiveNote() },
                openVault: openVault,
                goToFile: goToFile,
                toggleViewMode: { noteViewMode = noteViewMode.next() },
                createNote: beginNewNote,
                createFolder: { store.createFolder() },
                requestDelete: requestDelete,
                refresh: refreshVault,
                findInNote: findInNote,
                findInVault: {
                    vaultSearchQuery = ""
                    showVaultSearch = true
                },
                toggleBacklinks: { showBacklinks.toggle() },
                newTab: newTab,
                openInNewTab: openSelectionInNewTab,
                closeTab: { closeTab(id: tabs.selectedTabID) },
                isVaultOpen: store.rootURL != nil,
                hasOpenNote: editor.fileURL != nil,
                canDeleteSelection: store.selectedNode() != nil,
                canOpenInNewTab: store.selectedFileURL() != nil,
                canFindInNote: editor.fileURL != nil
            ))
    }

    @ViewBuilder
    private var rootShell: some View {
        if store.rootURL == nil {
            ContentUnavailableView {
                VStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("No Vault Open")
                        .font(LyraFonts.title)
                }
            } description: {
                Text("Open a folder of Markdown files to begin.")
                    .font(LyraFonts.body)
            } actions: {
                Button("Open Vault…") {
                    openVault()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LyraTheme.paperColor)
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
                onExportNotePDF: { pdfExport.exportNote($0) }
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
        .sheet(item: Binding(
            get: { wikiFlow.prompt },
            set: { wikiFlow.prompt = $0 }
        )) { prompt in
            WikiFollowSheet(
                prompt: prompt,
                onPick: { url in
                    wikiFlow.cancelPrompt()
                    wikiFlow.open(url)
                },
                onCreate: { dest in
                    wikiFlow.cancelPrompt()
                    wikiFlow.create(at: dest)
                },
                onCancel: { wikiFlow.cancelPrompt() }
            )
        }
        .alert(
            "Update links?",
            isPresented: Binding(
                get: { pendingLinkUpdate != nil },
                set: { if !$0 { pendingLinkUpdate = nil } }
            ),
            presenting: pendingLinkUpdate
        ) { update in
            Button("Update Links") { applyLinkUpdate(update) }
            Button("Don’t Update", role: .cancel) {}
        } message: { update in
            Text(linkUpdateMessage(update))
        }
        .sheet(isPresented: $showVaultSearch) {
            VaultSearchPalette(
                query: $vaultSearchQuery,
                search: { store.searchNoteBodies(query: $0, liveBodies: liveBodies()) },
                onOpen: { url in
                    showVaultSearch = false
                    wikiFlow.open(url)
                },
                onClose: { showVaultSearch = false }
            )
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
            pdfExport.exportActiveNote()
        } label: {
            Label("Export PDF", systemImage: "doc.richtext")
        }
        .disabled(editor.fileURL == nil)
        .help("Export current note to PDF")

        Toggle(isOn: $showBacklinks) {
            Label("Backlinks", systemImage: "link")
        }
        .toggleStyle(.button)
        .disabled(editor.fileURL == nil)
        .help("Show or hide backlinks")

        saveStatusLabel
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        if editor.lastSaveFailed {
            Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Last save failed — press ⌘S to retry")
        } else if backgroundSaveFailed {
            Label("Background tab save failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("A background tab failed to save — select it to retry")
        } else if editor.conflictDeferred {
            Label("Autosave paused", systemImage: "pause.circle")
                .foregroundStyle(.orange)
                .help("Conflict deferred — press ⌘S to resolve")
        }
        // Dirty state: traffic-light close button via DocumentEditedReader (no grey Unsaved label).
    }

    private var backgroundSaveFailed: Bool {
        tabs.tabs.contains { $0.editor !== editor && $0.editor.lastSaveFailed }
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
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    NoteTitleBar(
                        title: NoteTitle.displayTitle(fileURL: editor.fileURL),
                        breadcrumb: NoteTitle.breadcrumb(fileURL: editor.fileURL, vaultRoot: store.rootURL),
                        // Bound to the note shown when this title bar was built:
                        // a focus-loss commit that lands after a tab switch must
                        // not rename the newly selected note.
                        onCommit: { [noteURL = editor.fileURL] title in
                            commitNoteTitle(title, for: noteURL)
                        }
                    )
                    .id(editor.fileURL?.path)
                    noteContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            EditorStatusBar(
                                text: editor.text,
                                created: editor.createdAt,
                                lastSaved: editor.lastSavedAt
                            )
                            .padding(14)
                        }
                }
                .background(LyraTheme.paperColor)
                if showBacklinks, let url = editor.fileURL {
                    Rectangle()
                        .fill(LyraTheme.hairlineColor)
                        .frame(width: 1)
                    BacklinksInspector(
                        items: backlinkItems,
                        onOpen: { wikiFlow.open($0) },
                        onHide: { showBacklinks = false }
                    )
                    .task(id: BacklinksKey(path: url.path, text: editor.text, indexVersion: store.indexVersion)) {
                        await refreshBacklinks(for: url)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Backlinks walk every open tab's text, so they refresh after a short
    /// typing pause instead of on every keystroke. A different note updates at once.
    private func refreshBacklinks(for url: URL) async {
        if url.path == backlinksPath {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
        }
        backlinkItems = store.backlinks(to: url, liveBodies: liveBodies())
        backlinksPath = url.path
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
                viewOwner: editor,
                onEdit: { editor.noteEdited() },
                onPasteError: { store.present(context: .pasteImage, message: $0) },
                onWikiLink: { wikiFlow.followLink($0, from: editor.fileURL) },
                findBarToken: findBarToken,
                onFindBarShown: { findBarToken = 0 }
            )
            // Per-file identity. The text view itself is kept by the editor,
            // so undo, caret, and scroll survive tab switches and ⌘E.
            .id(editor.fileURL?.path)
        case .reading:
            MarkdownPreviewView(
                text: editor.text,
                noteDirectory: editor.fileURL?.deletingLastPathComponent(),
                vaultRoot: store.rootURL,
                onWikiLink: { wikiFlow.followLink($0, from: editor.fileURL) },
                onNoteLink: { wikiFlow.open($0) }
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
            Self.flushEditorError(editorRef, presentingOn: store)
        }
    }

    // MARK: - Lifecycle / vault

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            refreshVault()
        } else {
            // A deferred conflict stays deferred: switching apps must not
            // bring its dialog back.
            let failures = tabs.tabs.compactMap { tab in
                tab.editor.saveUnlessDeferred() ? nil : tab.editor
            }
            handleEditorSaveFailures(failures)
        }
    }

    /// ⌘R and window activation: rescan the tree, and let clean open notes
    /// pick up edits made outside Lyra (git pull, scripts, other editors).
    private func refreshVault() {
        guard store.rootURL != nil else { return }
        store.refresh()
        for tab in tabs.tabs {
            tab.editor.syncWithDiskIfClean()
        }
    }

    private func handleBackgroundSaveFailure() {
        guard let failed = tabs.tabs.first(where: { $0.editor !== editor && $0.editor.hasError })?.editor else {
            didAlertBackgroundSaveFailure = false
            return
        }
        guard !didAlertBackgroundSaveFailure else { return }
        didAlertBackgroundSaveFailure = true
        // Do not steal the selected tab. Ordinary errors can be flushed here;
        // conflicts/missing files need their tab-specific dialogs.
        if failed.hasExternalConflict || failed.hasMissingFile {
            store.present(
                context: .saveNote,
                message: "A background tab needs review before it can save. Select that tab to resolve it."
            )
        } else {
            Self.flushEditorError(failed, presentingOn: store)
        }
    }

    private func handleHasErrorChange(_ has: Bool) {
        // Surface autosave failures once; the toolbar indicator covers the ongoing state.
        if has && !didAlertSaveFailure {
            didAlertSaveFailure = true
            Self.flushEditorError(editor, presentingOn: store)
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
        // Already have a vault — open the chosen folder in a new window bound
        // to this pick, not to whatever URL happens to be next in a queue.
        let token = AppSession.shared.setPendingVaultURL(url)
        if let openNewVaultWindow {
            openNewVaultWindow(token)
        } else {
            AppSession.shared.discardPendingVaultURL(for: token)
            store.openVault(at: url)
        }
    }

    /// Empty-tab “Go to file” / ⌘O when a vault is open: pick a Markdown note and open it.
    private func goToFile() {
        guard let root = store.rootURL else {
            openVault()
            return
        }
        switch VaultNotePicker.pick(vaultRoot: root) {
        case .note(let url):
            store.selection = url.path
            wikiFlow.activate(url)
        case .outsideVault:
            store.present(
                context: .openNote,
                message: UserFacingError.message(
                    context: .openNote,
                    detail: "Go to File opens Markdown notes inside this vault. Open Vault… for another folder."
                )
            )
        case .cancelled:
            break
        }
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
        // Flush affected tabs before touching the filesystem, then close them
        // only after the trash operation succeeds.
        let path = node.url.path
        let affected = tabs.tabs.filter { tab in
            guard let openPath = tab.editor.fileURL?.path else { return false }
            return openPath == path || (node.isDirectory && openPath.hasPrefix(path + "/"))
        }
        for tab in affected {
            if !tab.editor.saveIfNeeded() {
                Self.flushEditorError(tab.editor, presentingOn: store)
                return
            }
        }
        guard store.deleteSelected() else { return }
        for tab in affected {
            if !tab.editor.close() {
                Self.flushEditorError(tab.editor, presentingOn: store)
                return
            }
        }
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
        renameItem(at: node.url, isDirectory: node.isDirectory, to: newName)
    }

    /// Title field commit for the note at `url`: rename the file. The first
    /// heading is not the name. Returns `false` when nothing was renamed.
    private func commitNoteTitle(_ newTitle: String, for url: URL?) -> Bool {
        guard let url, tabs.tabs.contains(where: { $0.editor.fileURL?.path == url.path }) else {
            // That note is no longer open here; nothing to rename.
            return false
        }
        let result = NoteTitle.applyingTitle(newTitle, to: "")
        if let error = result.error {
            store.present(context: .rename, message: error)
            return false
        }
        guard let stem = result.renamedStem else { return false }
        guard stem != url.deletingPathExtension().lastPathComponent else { return true }
        return renameItem(at: url, isDirectory: false, to: stem + ".md")
    }

    /// Flush editors, rename on disk, relocate open tabs, and offer to point
    /// `[[links]]` at a renamed note.
    private func renameItem(at url: URL, isDirectory: Bool, to newName: String) -> Bool {
        for tab in tabs.tabs {
            guard tab.editor.saveIfNeeded() else {
                Self.flushEditorError(tab.editor, presentingOn: store)
                return false
            }
        }
        // Capture links to the old name before the rescan forgets it.
        let resolver = store.linkResolver
        let linkSources = isDirectory ? [] : store.backlinks(to: url, liveBodies: liveBodies())
        store.selection = url.path
        guard let newURL = store.renameSelected(to: newName) else {
            return false
        }
        tabs.relocateOpenNotes(oldPath: url.path, newURL: newURL)
        if !linkSources.isEmpty {
            pendingLinkUpdate = PendingLinkUpdate(
                oldURL: url,
                newStem: newURL.deletingPathExtension().lastPathComponent,
                sources: linkSources,
                resolver: resolver
            )
        }
        return true
    }

    private func linkUpdateMessage(_ update: PendingLinkUpdate) -> String {
        let oldStem = update.oldURL.deletingPathExtension().lastPathComponent
        let count = update.sources.count
        let notes = count == 1 ? "1 note links" : "\(count) notes link"
        return "\(notes) to “\(oldStem)”. Point those links at “\(update.newStem)”?"
    }

    /// Rewrite links in every note that pointed at the renamed one. Open
    /// notes change in their tab (autosave writes them); closed notes go
    /// through the normal save path, so conflict and vault checks apply.
    private func applyLinkUpdate(_ update: PendingLinkUpdate) {
        var failures = 0
        for source in update.sources {
            if let tab = tabs.tabs.first(where: { $0.editor.fileURL?.path == source.url.path }) {
                if let rewritten = update.resolver.rewritingLinks(
                    in: tab.editor.text,
                    from: update.oldURL,
                    toStem: update.newStem
                ) {
                    tab.editor.text = rewritten
                    tab.editor.noteEdited()
                }
                continue
            }
            let editor = EditorViewModel()
            editor.vaultRoot = store.rootURL
            guard editor.open(url: source.url) else {
                failures += 1
                continue
            }
            guard let rewritten = update.resolver.rewritingLinks(
                in: editor.text,
                from: update.oldURL,
                toStem: update.newStem
            ) else { continue }
            editor.text = rewritten
            editor.isDirty = true
            if !editor.saveIfNeeded() {
                failures += 1
            }
        }
        if failures > 0 {
            store.present(
                context: .rename,
                message: UserFacingError.message(
                    context: .rename,
                    detail: "Lyra couldn't update links in \(failures == 1 ? "1 note" : "\(failures) notes"). "
                        + "Those links still use the old name."
                )
            )
        }
        store.refresh()
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

        wikiFlow.activate(node.url)
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
                Self.flushEditorError(failed, presentingOn: store)
            }
        )
        if ok {
            Self.flushEditorError(tabs.selectedEditor, presentingOn: store)
        }
        // On failure, selection stays on the chosen file; failed editor error already flushed via onFailed.
    }


    /// Canonical transient-error surfacing shared by the window shell and its
    /// flows: conflict / missing-file cases belong to their own dialogs;
    /// anything else presents once and clears.
    static func flushEditorError(_ ed: EditorViewModel, presentingOn store: VaultStore) {
        guard !ed.hasExternalConflict, !ed.hasMissingFile else { return }
        guard let last = ed.lastError else { return }
        store.present(error: last.error, context: last.context)
        ed.lastError = nil
    }

    /// Select the tab that owns a failed editor so conflict/missing-file
    /// dialogs and ordinary save alerts are attached to the right note.
    private func handleEditorSaveFailures(_ failures: [EditorViewModel]) {
        if let failed = failures.first(where: { editor in
            tabs.tabs.contains { $0.editor === editor }
        }) {
            selectTab(containing: failed)
            Self.flushEditorError(failed, presentingOn: store)
            return
        }
        // No live tab owns the failure. In a single visible window this must be
        // a retained editor from a closed window; surface quit cancellation.
        // With multiple windows, the owning window handles its own failure.
        if !failures.isEmpty, NSApp.windows.filter(\.isVisible).count <= 1 {
            store.present(
                context: .saveNote,
                message: "Lyra couldn't save changes from a closed note. Quit was cancelled; reopen the vault to retry."
            )
        }
    }

    private func selectTab(containing editor: EditorViewModel) {
        guard let tab = tabs.tabs.first(where: { $0.editor === editor }) else { return }
        tabs.select(tab.id)
        store.selection = tab.editor.fileURL?.path
    }


    /// ⌘F: find bar in Source. From Reading, switch to Source first so the
    /// shortcut is never a silent no-op.
    private func findInNote() {
        guard editor.fileURL != nil else { return }
        if noteViewMode == .source {
            findBarToken += 1
            return
        }
        noteViewMode = .source
        DispatchQueue.main.async {
            findBarToken += 1
        }
    }

    private func liveBodies() -> [String: String] {
        var bodies: [String: String] = [:]
        for tab in tabs.tabs {
            guard let path = tab.editor.fileURL?.path else { continue }
            bodies[path] = tab.editor.text
        }
        return bodies
    }

}
