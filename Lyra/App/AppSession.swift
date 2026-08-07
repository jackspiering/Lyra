import AppKit
import Foundation

/// Tracks every open note editor (all tabs in all vault windows) so quit can flush dirty buffers.
@MainActor
final class AppSession {
    static let shared = AppSession()

    /// Only the first vault window restores the last-opened bookmark.
    private(set) var didRestoreLaunchVault = false
    /// Folders chosen for newly created windows. Keep request order so two
    /// Open Vault actions cannot overwrite one another before onAppear runs.
    private var pendingVaultURLs: [URL] = []

    private struct Entry {
        // Keep a failed editor alive across an unexpected scene teardown so a
        // cancelled quit can retry the save instead of losing its buffer.
        var editor: EditorViewModel?
        weak var store: VaultStore?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// Returns true once — used by `VaultStore` init so only one window auto-opens the last vault.
    func claimLaunchVaultRestore() -> Bool {
        if didRestoreLaunchVault { return false }
        didRestoreLaunchVault = true
        return true
    }

    func setPendingVaultURL(_ url: URL) {
        pendingVaultURLs.append(url)
    }

    func takePendingVaultURL() -> URL? {
        guard !pendingVaultURLs.isEmpty else { return nil }
        return pendingVaultURLs.removeFirst()
    }

    func register(editor: EditorViewModel, store: VaultStore) {
        editor.vaultRoot = store.rootURL
        entries[ObjectIdentifier(editor)] = Entry(editor: editor, store: store)
        prune()
    }

    func updateVaultRoot(for store: VaultStore, root: URL?) {
        for key in entries.keys {
            guard let entry = entries[key], entry.store === store, let editor = entry.editor else { continue }
            editor.vaultRoot = root
        }
    }

    func unregister(editor: EditorViewModel) {
        entries.removeValue(forKey: ObjectIdentifier(editor))
    }

    /// Returns editors that blocked save (conflict / missing / I/O).
    @discardableResult
    func saveAllEditors() -> [EditorViewModel] {
        prune()
        var failed: [EditorViewModel] = []
        for entry in entries.values {
            guard let editor = entry.editor else { continue }
            if !editor.saveIfNeeded() {
                failed.append(editor)
            }
        }
        return failed
    }

    func releaseAllVaultAccess() {
        prune()
        for entry in entries.values {
            entry.store?.releaseAccess()
        }
    }

    private func prune() {
        entries = entries.filter { $0.value.editor != nil }
    }
}
