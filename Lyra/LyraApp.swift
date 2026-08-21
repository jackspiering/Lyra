import AppKit
import SwiftUI

extension Notification.Name {
    static let lyraSaveNote = Notification.Name("lyraSaveNote")
    static let lyraExportPDF = Notification.Name("lyraExportPDF")
    static let lyraNewNote = Notification.Name("lyraNewNote")
    static let lyraNewFolder = Notification.Name("lyraNewFolder")
    static let lyraOpenVault = Notification.Name("lyraOpenVault")
    /// Open a Markdown note from the current vault (⌘O when a vault is open).
    static let lyraGoToFile = Notification.Name("lyraGoToFile")
    static let lyraToggleViewMode = Notification.Name("lyraToggleViewMode")
    static let lyraRefreshVault = Notification.Name("lyraRefreshVault")
    /// Move the sidebar selection to the Trash (⌘⌫).
    static let lyraDeleteSelection = Notification.Name("lyraDeleteSelection")
    /// Show the Source find bar (⌘F).
    static let lyraFindInNote = Notification.Name("lyraFindInNote")
    /// Open in-memory vault full-text search (⇧⌘F).
    static let lyraFindInVault = Notification.Name("lyraFindInVault")
    /// Show or hide the backlinks inspector.
    static let lyraToggleBacklinks = Notification.Name("lyraToggleBacklinks")
    /// New empty note tab in the key vault window (⌘T).
    static let lyraNewTab = Notification.Name("lyraNewTab")
    /// Open the sidebar selection in a new note tab (File → Open in New Tab).
    static let lyraOpenInNewTab = Notification.Name("lyraOpenInNewTab")
    /// Close the selected note tab (File → Close Tab). Last tab becomes empty.
    static let lyraCloseTab = Notification.Name("lyraCloseTab")
    /// Posted when quit was cancelled because one or more saves failed. The
    /// owning window surfaces the first failed editor.
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
        NotificationCenter.default.post(name: .lyraQuitSaveFailed, object: failed)
        return .terminateCancel
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
            }
        }
        .onChange(of: appearanceRaw) { _, new in
            AppearanceController.apply(rawValue: new)
        }
        .onDisappear {
            for editor in tabs.allEditors() {
                if editor.saveIfNeeded() {
                    AppSession.shared.unregister(editor: editor)
                } else {
                    // Keep failed editor registered so AppSession can retry on quit;
                    // do not unregister — prune keeps weak entry alive.
                }
            }
            // Always balance startAccessingSecurityScopedResource, even when a save
            // failed. Per-window scope must not leak across window close + reopen.
            store.releaseAccess()
        }
    }
}

@main
struct LyraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        LyraFonts.registerBundledFonts()
        GeneralPreferences.migrateConfirmDeleteIfNeeded()
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
                    NotificationCenter.default.post(name: .lyraNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Folder") {
                    NotificationCenter.default.post(name: .lyraNewFolder, object: nil)
                }

                Button("New Tab") {
                    NotificationCenter.default.post(name: .lyraNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open in New Tab") {
                    NotificationCenter.default.post(name: .lyraOpenInNewTab, object: nil)
                }

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .lyraCloseTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
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
            }
            CommandGroup(after: .newItem) {
                Button("Go to File…") {
                    NotificationCenter.default.post(name: .lyraGoToFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Vault…") {
                    NotificationCenter.default.post(name: .lyraOpenVault, object: nil)
                }

                Button("Refresh Vault") {
                    NotificationCenter.default.post(name: .lyraRefreshVault, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Move to Trash") {
                    NotificationCenter.default.post(name: .lyraDeleteSelection, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            CommandMenu("View") {
                Button("Toggle Source / Reading") {
                    NotificationCenter.default.post(name: .lyraToggleViewMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Backlinks") {
                    NotificationCenter.default.post(name: .lyraToggleBacklinks, object: nil)
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    NotificationCenter.default.post(name: .lyraFindInNote, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Search Vault…") {
                    NotificationCenter.default.post(name: .lyraFindInVault, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
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
