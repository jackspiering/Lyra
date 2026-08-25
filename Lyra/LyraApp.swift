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
    @FocusedValue(\.vaultCommands) private var vaultCommands: VaultCommands?

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
                    vaultCommands?.createNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Folder") {
                    vaultCommands?.createFolder()
                }

                Button("New Tab") {
                    vaultCommands?.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open in New Tab") {
                    vaultCommands?.openInNewTab()
                }

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
            }
            CommandGroup(after: .importExport) {
                Button("Export PDF…") {
                    vaultCommands?.exportPDF()
                }
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

                Divider()

                Button("Move to Trash") {
                    vaultCommands?.requestDelete()
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            CommandMenu("View") {
                Button("Toggle Source / Reading") {
                    vaultCommands?.toggleViewMode()
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Backlinks") {
                    vaultCommands?.toggleBacklinks()
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    vaultCommands?.findInNote()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Search Vault…") {
                    vaultCommands?.findInVault()
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
