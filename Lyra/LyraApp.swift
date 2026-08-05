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
    /// Move the sidebar selection to the Trash (⌘⌫).
    static let lyraDeleteSelection = Notification.Name("lyraDeleteSelection")
    /// Focus the sidebar vault name search field (⌘F). No in-note find yet.
    static let lyraFocusVaultSearch = Notification.Name("lyraFocusVaultSearch")
    /// New empty note tab in the key vault window (⌘T).
    static let lyraNewTab = Notification.Name("lyraNewTab")
    /// Close the selected note tab (File → Close Tab). Last tab becomes empty.
    static let lyraCloseTab = Notification.Name("lyraCloseTab")
    /// Posted when quit was cancelled because a save failed; ContentView surfaces the error.
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
        if AppSession.shared.saveAllEditors() {
            return .terminateNow
        }
        NotificationCenter.default.post(name: .lyraQuitSaveFailed, object: nil)
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppSession.shared.releaseAllVaultAccess()
    }
}

/// One vault window: one store + note-tab controller (multi-vault = multiple windows).
struct VaultWindowRoot: View {
    @State private var store = VaultStore()
    @State private var tabs = NoteTabController()
    @AppStorage("lyra.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @Environment(\.openWindow) private var openWindow

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        ContentView(store: store, tabs: tabs, openNewVaultWindow: {
            openWindow(id: "vault")
        })
        // nil for System so SwiftUI does not pin light/dark after a forced scheme.
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            AppearanceController.apply(rawValue: appearanceRaw)
            for editor in tabs.allEditors() {
                AppSession.shared.register(editor: editor, store: store)
            }
            if let pending = AppSession.shared.takePendingVaultURL() {
                store.openVault(at: pending)
            }
        }
        .onChange(of: appearanceRaw) { _, new in
            AppearanceController.apply(rawValue: new)
        }
        .onDisappear {
            for editor in tabs.allEditors() {
                _ = editor.saveIfNeeded()
                AppSession.shared.unregister(editor: editor)
            }
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
        WindowGroup(id: "vault") {
            VaultWindowRoot()
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
                Button("Open Vault…") {
                    NotificationCenter.default.post(name: .lyraOpenVault, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

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
            }
            // `.find` is not a CommandGroupPlacement; hang vault search after text editing.
            CommandGroup(after: .textEditing) {
                Button("Find in Vault") {
                    NotificationCenter.default.post(name: .lyraFocusVaultSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
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
            openWindow(id: "vault")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
