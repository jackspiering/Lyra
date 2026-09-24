import SwiftUI

/// Window chrome (dialogs + quit-save-failure routing) — kept out of `ContentView.body` so the type-checker stays happy.
struct ContentViewChrome: ViewModifier {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @Binding var showDeleteConfirm: Bool
    @Binding var showNewNoteSheet: Bool
    var onSelectionChange: (VaultNode.ID?) -> Void
    var onHasErrorChange: (Bool) -> Void
    var flushEditorError: () -> Void
    var quitSaveFailed: ([EditorViewModel]) -> Void
    var newNoteSheet: () -> AnyView
    var deleteConfirmSheet: () -> AnyView

    init(
        store: VaultStore,
        editor: EditorViewModel,
        showDeleteConfirm: Binding<Bool>,
        showNewNoteSheet: Binding<Bool>,
        onSelectionChange: @escaping (VaultNode.ID?) -> Void,
        onHasErrorChange: @escaping (Bool) -> Void,
        flushEditorError: @escaping () -> Void,
        quitSaveFailed: @escaping ([EditorViewModel]) -> Void,
        newNoteSheet: @escaping () -> some View,
        deleteConfirmSheet: @escaping () -> some View
    ) {
        self.store = store
        self.editor = editor
        self._showDeleteConfirm = showDeleteConfirm
        self._showNewNoteSheet = showNewNoteSheet
        self.onSelectionChange = onSelectionChange
        self.onHasErrorChange = onHasErrorChange
        self.flushEditorError = flushEditorError
        self.quitSaveFailed = quitSaveFailed
        self.newNoteSheet = { AnyView(newNoteSheet()) }
        self.deleteConfirmSheet = { AnyView(deleteConfirmSheet()) }
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
            // App-global by design — the failing editor may belong to a
            // background window, so every vault window observes and claims
            // its own editors from the payload.
            .onReceive(NotificationCenter.default.publisher(for: .lyraQuitSaveFailed)) { notification in
                let failures = notification.object as? [EditorViewModel] ?? []
                quitSaveFailed(failures)
            }
    }
}

struct ContentViewDialogs: ViewModifier {
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
                    set: { if !$0 { editor.deferConflict() } }
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
                    set: { if !$0 { editor.deferConflict(); editor.hasMissingFile = false } }
                ),
                titleVisibility: .visible
            ) {
                Button("Save Here") {
                    if !editor.saveIfNeeded(force: true) {
                        flushEditorError()
                    }
                }
                Button("Close Note", role: .destructive) {
                    editor.discardAndClose()
                    store.selection = nil
                }
                Button("Cancel", role: .cancel) {
                    editor.deferConflict()
                    editor.hasMissingFile = false
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
            .confirmationDialog(
                "Your vault moved",
                isPresented: Binding(
                    get: { store.needsStaleVaultConfirmation },
                    set: { if !$0 { store.declineStaleVaultRestore() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Open This Folder") {
                    store.confirmStaleVaultRestore()
                }
                Button("Choose Folder…") {
                    if let url = VaultFolderPicker.pick(
                        message: "Your vault folder moved. Choose it again."
                    ) {
                        store.replaceStaleVaultRestore(with: url)
                    } else {
                        store.declineStaleVaultRestore()
                    }
                }
                Button("Not Now", role: .cancel) {
                    store.declineStaleVaultRestore()
                }
            } message: {
                Text("Lyra found \(staleRestoreDisplayPath()). Open it only if this is the folder you expect.")
            }
    }

    private func staleRestoreDisplayPath() -> String {
        guard let url = store.staleRestoreURL else {
            return "a vault folder that may have moved"
        }
        let parent = url.deletingLastPathComponent().lastPathComponent
        let leaf = url.lastPathComponent
        let display = parent.isEmpty ? leaf : "\(parent)/\(leaf)"
        return "“\(display)” that may have moved"
    }
}
