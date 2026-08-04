import AppKit
import Foundation

/// Tracks open vault windows so quit can flush every dirty editor.
@MainActor
final class AppSession {
    static let shared = AppSession()

    /// Only the first vault window restores the last-opened bookmark.
    private(set) var didRestoreLaunchVault = false
    /// Folder chosen in window A to open in a newly created window B.
    private var pendingVaultURL: URL?

    private struct Entry {
        weak var editor: EditorViewModel?
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
        pendingVaultURL = url
    }

    func takePendingVaultURL() -> URL? {
        defer { pendingVaultURL = nil }
        return pendingVaultURL
    }

    func register(editor: EditorViewModel, store: VaultStore) {
        entries[ObjectIdentifier(editor)] = Entry(editor: editor, store: store)
        prune()
    }

    func unregister(editor: EditorViewModel) {
        entries.removeValue(forKey: ObjectIdentifier(editor))
    }

    /// Returns false if any editor blocked save (conflict / missing / I/O).
    @discardableResult
    func saveAllEditors() -> Bool {
        prune()
        var ok = true
        for entry in entries.values {
            guard let editor = entry.editor else { continue }
            if !editor.saveIfNeeded() {
                ok = false
            }
        }
        return ok
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
