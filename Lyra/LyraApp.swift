import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when quit was cancelled because one or more saves failed. The
    /// owning window surfaces the first failed editor. App-global by design:
    /// the failing editor may belong to a background window, so this cannot
    /// ride the per-window `VaultCommands` focused value.
    static let lyraQuitSaveFailed = Notification.Name("lyraQuitSaveFailed")
}

/// Coordinates quit-time save so unsaved work is not discarded silently.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Architecture: custom NoteTabBar only — no NSWindow native tabbing (+ in title bar).
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let failed = AppSession.shared.saveAllEditors()
        if failed.isEmpty {
            return .terminateNow
        }
        NSApp.activate(ignoringOtherApps: true)
        let orphaned = AppSession.shared.orphaned(failed)
        if orphaned.count < failed.count {
            // An open window owns at least one failure and shows its recovery.
            NotificationCenter.default.post(name: .lyraQuitSaveFailed, object: failed)
            return .terminateCancel
        }
        // Only notes from closed windows failed; nothing else would ever
        // surface them, so ask here instead of cancelling quit silently.
        guard confirmDiscarding(orphaned) else { return .terminateCancel }
        AppSession.shared.discard(orphaned)
        return .terminateNow
    }

    private func confirmDiscarding(_ editors: [EditorViewModel]) -> Bool {
        let names = editors
            .compactMap { $0.fileURL?.deletingPathExtension().lastPathComponent }
            .joined(separator: ", ")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some notes couldn't be saved"
        alert.informativeText = "Changes to \(names.isEmpty ? "a note" : names) from a closed window "
            + "couldn't be written to disk. Quit anyway and lose those changes?"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard and Quit")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppSession.shared.releaseAllVaultAccess()
    }
}

/// One vault window: one store + note-tab controller (multi-vault = multiple windows).
struct VaultWindowRoot: View {
    /// Identifies this window for the Open Vault handoff. Nil on a restored
    /// scene that has not received a value yet.
    var handoffID: UUID?
    @State private var store = VaultStore()
    @State private var tabs = NoteTabController()
    /// This window's vault, so a relaunch reopens every vault window.
    @SceneStorage("lyra.windowVaultBookmark") private var windowVaultBookmark: Data?
    @AppStorage("lyra.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @Environment(\.openWindow) private var openWindow

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        ContentView(store: store, tabs: tabs, openNewVaultWindow: { token in
            openWindow(id: "vault", value: token)
        })
        // nil for System so SwiftUI does not pin light/dark after a forced scheme.
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            AppearanceController.apply(rawValue: appearanceRaw)
            for editor in tabs.allEditors() {
                AppSession.shared.register(editor: editor, store: store)
            }
            if let handoffID,
               let pending = AppSession.shared.takePendingVaultURL(for: handoffID) {
                store.openVault(at: pending)
            } else if let windowVaultBookmark {
                AppSession.shared.markLaunchVaultRestored()
                store.restoreVault(fromBookmark: windowVaultBookmark)
            } else if AppSession.shared.claimLaunchVaultRestore() {
                store.restoreLastVault()
            }
        }
        .onChange(of: appearanceRaw) { _, new in
            AppearanceController.apply(rawValue: new)
        }
        .onChange(of: store.rootBookmark) { _, bookmark in
            if let bookmark {
                windowVaultBookmark = bookmark
            }
        }
        .onDisappear {
            AppSession.shared.windowClosed(store: store)
            var hasFailedEditor = false
            for editor in tabs.allEditors() {
                if editor.saveIfNeeded() {
                    AppSession.shared.unregister(editor: editor)
                } else {
                    // Keep failed editor registered so AppSession can retry on quit;
                    // do not unregister — the retained entry keeps its store alive.
                    hasFailedEditor = true
                }
            }
            // Balance security-scoped access only when every editor saved.
            // A retained failed editor keeps its store/scope until a later save
            // or application termination.
            if !hasFailedEditor {
                store.releaseAccess()
            }
        }
    }
}

@main
struct LyraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.vaultCommands) private var vaultCommands: VaultCommands?

    private var isVaultOpen: Bool { vaultCommands?.isVaultOpen == true }
    private var hasOpenNote: Bool { vaultCommands?.hasOpenNote == true }

    init() {
        LyraFonts.registerBundledFonts()
    }

    var body: some Scene {
        // One vault per window — open multiple windows for multiple vaults.
        WindowGroup(id: "vault", for: UUID.self) { $handoffID in
            VaultWindowRoot(handoffID: handoffID)
        } defaultValue: {
            UUID()
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewVaultWindowButton()

                Button("New Note") {
                    vaultCommands?.createNote()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!isVaultOpen)

                Button("New Folder") {
                    vaultCommands?.createFolder()
                }
                .disabled(!isVaultOpen)

                Button("New Tab") {
                    vaultCommands?.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!isVaultOpen)

                Button("Open in New Tab") {
                    vaultCommands?.openInNewTab()
                }
                .disabled(vaultCommands?.canOpenInNewTab != true)

                Button("Close Tab") {
                    vaultCommands?.closeTab()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    vaultCommands?.save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasOpenNote)
            }
            CommandGroup(after: .importExport) {
                Button("Export PDF…") {
                    vaultCommands?.exportPDF()
                }
                .disabled(!hasOpenNote)
            }
            CommandGroup(after: .newItem) {
                Button("Go to File…") {
                    vaultCommands?.goToFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Vault…") {
                    vaultCommands?.openVault()
                }

                Button("Refresh Vault") {
                    vaultCommands?.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!isVaultOpen)

                Divider()

                Button("Move to Trash") {
                    vaultCommands?.requestDelete()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(vaultCommands?.canDeleteSelection != true)
            }
            // Joins the system View menu (toolbar, sidebar, full screen)
            // instead of adding a second top-level "View" menu.
            CommandGroup(before: .toolbar) {
                Button("Toggle Source / Reading") {
                    vaultCommands?.toggleViewMode()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!hasOpenNote)

                Button("Backlinks") {
                    vaultCommands?.toggleBacklinks()
                }
                .disabled(!hasOpenNote)

                Divider()

                Button("Bigger") {
                    vaultCommands?.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!hasOpenNote)

                Button("Smaller") {
                    vaultCommands?.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!hasOpenNote)

                Button("Actual Size") {
                    vaultCommands?.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!hasOpenNote)

                Divider()
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    vaultCommands?.findInNote()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(vaultCommands?.canFindInNote != true)

                Button("Search Vault…") {
                    vaultCommands?.findInVault()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!isVaultOpen)
            }
        }

        Settings {
            SettingsView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 480, height: 420)
    }
}

/// File → New Window needs `openWindow` from the environment.
private struct NewVaultWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "vault", value: UUID())
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
