import Combine
import SwiftUI

/// Bridges File-menu bar commands (posted as notifications from `LyraApp`) to this window.
/// Each vault window observes all commands and runs them only when it is the key window.
struct ContentViewCommands: ViewModifier {
    var shouldHandle: () -> Bool
    var exportPDF: () -> Void
    var openVault: () -> Void
    var goToFile: () -> Void
    var toggleViewMode: () -> Void
    var createNote: () -> Void
    var createFolder: () -> Void
    var requestDelete: () -> Void
    var refresh: () -> Void
    var save: () -> Void
    var quitSaveFailed: () -> Void
    var focusVaultSearch: () -> Void
    var newTab: () -> Void
    var openInNewTab: () -> Void
    var closeTab: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .lyraSaveNote)) { _ in
                guard shouldHandle() else { return }
                save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraExportPDF)) { _ in
                guard shouldHandle() else { return }
                exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraNewNote)) { _ in
                guard shouldHandle() else { return }
                createNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraNewFolder)) { _ in
                guard shouldHandle() else { return }
                createFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraGoToFile)) { _ in
                guard shouldHandle() else { return }
                goToFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraOpenVault)) { _ in
                guard shouldHandle() else { return }
                openVault()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraToggleViewMode)) { _ in
                guard shouldHandle() else { return }
                toggleViewMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraRefreshVault)) { _ in
                guard shouldHandle() else { return }
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraDeleteSelection)) { _ in
                guard shouldHandle() else { return }
                requestDelete()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraFocusVaultSearch)) { _ in
                guard shouldHandle() else { return }
                focusVaultSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraNewTab)) { _ in
                guard shouldHandle() else { return }
                newTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraOpenInNewTab)) { _ in
                guard shouldHandle() else { return }
                openInNewTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraCloseTab)) { _ in
                guard shouldHandle() else { return }
                closeTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .lyraQuitSaveFailed)) { _ in
                // All windows may surface; only key window needs UI (others already saved or clean).
                guard shouldHandle() else { return }
                quitSaveFailed()
            }
    }
}
