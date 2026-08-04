import AppKit
import SwiftUI

extension Notification.Name {
    static let lyraSaveNote = Notification.Name("lyraSaveNote")
    static let lyraExportPDF = Notification.Name("lyraExportPDF")
    static let lyraNewNote = Notification.Name("lyraNewNote")
    static let lyraNewFolder = Notification.Name("lyraNewFolder")
    static let lyraOpenVault = Notification.Name("lyraOpenVault")
    static let lyraToggleViewMode = Notification.Name("lyraToggleViewMode")
    static let lyraRefreshVault = Notification.Name("lyraRefreshVault")
    /// Posted when quit was cancelled because a save failed; ContentView surfaces the error.
    static let lyraQuitSaveFailed = Notification.Name("lyraQuitSaveFailed")
}

/// Coordinates quit-time save so unsaved work is not discarded silently.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var editor: EditorViewModel?
    weak var store: VaultStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editor else { return .terminateNow }
        if editor.saveIfNeeded() {
            return .terminateNow
        }
        // Save blocked (conflict, missing file, or I/O error) — cancel quit and let UI react.
        NotificationCenter.default.post(name: .lyraQuitSaveFailed, object: nil)
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.releaseAccess()
    }
}

@main
struct LyraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = VaultStore()
    @State private var editor = EditorViewModel()

    init() {
        LyraFonts.registerBundledFonts()
    }

    var body: some Scene {
        // Single main window — multi-window document architecture is a non-goal.
        Window("Lyra", id: "main") {
            ContentView(store: store, editor: editor)
                .onAppear {
                    appDelegate.editor = editor
                    appDelegate.store = store
                }
        }
        .commands {
            // Replace File → New Window with New Note / New Folder.
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .lyraNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store.rootURL == nil)

                Button("New Folder") {
                    NotificationCenter.default.post(name: .lyraNewFolder, object: nil)
                }
                .disabled(store.rootURL == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .lyraSaveNote, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Export PDF…") {
                    NotificationCenter.default.post(name: .lyraExportPDF, object: nil)
                }
                .disabled(editor.fileURL == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Open Vault…") {
                    NotificationCenter.default.post(name: .lyraOpenVault, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Refresh Vault") {
                    NotificationCenter.default.post(name: .lyraRefreshVault, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.rootURL == nil)
            }
            CommandMenu("View") {
                Button("Toggle Source / Reading") {
                    NotificationCenter.default.post(name: .lyraToggleViewMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(store.rootURL == nil)
            }
        }
    }
}
