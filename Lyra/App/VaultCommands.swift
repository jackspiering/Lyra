import SwiftUI

/// Per-window menu command surface, published with `focusedSceneValue` so the
/// key vault window answers File-menu and View-menu commands. When no vault
/// window has focus the menus see nil and their actions no-op — the same gate
/// the previous key-window notification checks provided. Quit-save failure is
/// not part of this surface: it may target a background window, so it stays on
/// an app-global notification observed by every vault window.
struct VaultCommands {
    var save: () -> Void
    var exportPDF: () -> Void
    var openVault: () -> Void
    var goToFile: () -> Void
    var toggleViewMode: () -> Void
    var createNote: () -> Void
    var createFolder: () -> Void
    var requestDelete: () -> Void
    var refresh: () -> Void
    var findInNote: () -> Void
    var findInVault: () -> Void
    var toggleBacklinks: () -> Void
    var newTab: () -> Void
    var openInNewTab: () -> Void
    var closeTab: () -> Void
}

private struct VaultCommandsKey: FocusedValueKey {
    typealias Value = VaultCommands
}

extension FocusedValues {
    /// Scene-scoped so each vault window publishes its own command set.
    var vaultCommands: VaultCommands? {
        get { self[VaultCommandsKey.self] }
        set { self[VaultCommandsKey.self] = newValue }
    }
}
