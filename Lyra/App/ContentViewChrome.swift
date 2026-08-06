import SwiftUI

/// Window chrome (dialogs + command routing) — kept out of `ContentView.body` so the type-checker stays happy.
struct ContentViewChrome: ViewModifier {
    @Bindable var store: VaultStore
    @Bindable var editor: EditorViewModel
    @Binding var showDeleteConfirm: Bool
    @Binding var showNewNoteSheet: Bool
    var onSelectionChange: (VaultNode.ID?) -> Void
    var onHasErrorChange: (Bool) -> Void
    var flushEditorError: () -> Void
    var exportPDF: () -> Void
    var openVault: () -> Void
    var goToFile: () -> Void
    var beginNewNote: () -> Void
    var requestDelete: () -> Void
    var toggleViewMode: () -> Void
    var focusVaultSearch: () -> Void
    var newTab: () -> Void
    var openInNewTab: () -> Void
    var closeTab: () -> Void
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
        goToFile: @escaping () -> Void,
        beginNewNote: @escaping () -> Void,
        requestDelete: @escaping () -> Void,
        toggleViewMode: @escaping () -> Void,
        focusVaultSearch: @escaping () -> Void,
        newTab: @escaping () -> Void,
        openInNewTab: @escaping () -> Void,
        closeTab: @escaping () -> Void,
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
        self.goToFile = goToFile
        self.beginNewNote = beginNewNote
        self.requestDelete = requestDelete
        self.toggleViewMode = toggleViewMode
        self.focusVaultSearch = focusVaultSearch
        self.newTab = newTab
        self.openInNewTab = openInNewTab
        self.closeTab = closeTab
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
                goToFile: goToFile,
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
                focusVaultSearch: focusVaultSearch,
                newTab: newTab,
                openInNewTab: openInNewTab,
                closeTab: closeTab
            ))
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
