import AppKit
import Foundation
import UniformTypeIdentifiers

/// PDF export orchestration for one vault window: gather the note body
/// (an open tab's buffer wins over disk), render off the main actor via
/// `NotePDFExporter`, then ask where to save. Rendering and layout run in a
/// detached task; panels and error state stay on the main actor.
@MainActor
final class PDFExportFlow {
    private let store: VaultStore
    private let tabs: NoteTabController
    /// Surfaces a failed pre-export save on the active note.
    private let flushError: (EditorViewModel) -> Void
    private var exportTask: Task<Void, Never>?
    /// A save panel is showing; another export must not stack a second one.
    private var isSavePanelOpen = false

    init(
        store: VaultStore,
        tabs: NoteTabController,
        flushError: @escaping (EditorViewModel) -> Void
    ) {
        self.store = store
        self.tabs = tabs
        self.flushError = flushError
    }

    /// File ▸ Export PDF / toolbar: export the note in the active tab.
    func exportActiveNote() {
        let editor = tabs.selectedEditor
        guard let noteURL = editor.fileURL else { return }
        _ = editor.saveIfNeeded()
        flushError(editor)
        export(markdown: editor.text, noteURL: noteURL)
    }

    /// Sidebar context menu: export any note; its open tab's buffer wins.
    func exportNote(_ node: VaultNode) {
        guard !node.isDirectory, store.rootURL != nil else { return }
        if let openTab = tabs.tabs.first(where: { $0.editor.fileURL?.path == node.url.path }) {
            _ = openTab.editor.saveIfNeeded()
            export(markdown: openTab.editor.text, noteURL: node.url)
            return
        }
        let nodeURL = node.url
        Task { @MainActor in
            do {
                let markdown = try await Task.detached(priority: .userInitiated) {
                    try String(contentsOf: nodeURL, encoding: .utf8)
                }.value
                export(markdown: markdown, noteURL: nodeURL)
            } catch {
                store.present(error: error, context: .exportPDF)
            }
        }
    }

    private func export(markdown: String, noteURL: URL) {
        guard !isSavePanelOpen, let vault = store.rootURL else { return }
        let window = NSApp.keyWindow
        let noteDirectory = noteURL.deletingLastPathComponent()
        let stem = noteURL.deletingPathExtension().lastPathComponent
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try NotePDFExporter.pdfData(
                        markdown: markdown,
                        noteDirectory: noteDirectory,
                        vaultRoot: vault,
                        documentTitle: stem
                    )
                }.value
                guard !Task.isCancelled else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.nameFieldStringValue = stem + ".pdf"
                panel.directoryURL = noteDirectory
                isSavePanelOpen = true
                if let window {
                    panel.beginSheetModal(for: window) { [weak self] resp in
                        self?.finishExport(resp, panel: panel, data: data)
                    }
                } else {
                    panel.begin { [weak self] resp in
                        self?.finishExport(resp, panel: panel, data: data)
                    }
                }
            } catch {
                store.present(error: error, context: .exportPDF)
            }
        }
    }

    private func finishExport(_ response: NSApplication.ModalResponse, panel: NSSavePanel, data: Data) {
        isSavePanelOpen = false
        guard response == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            store.present(error: error, context: .exportPDF)
        }
    }
}
