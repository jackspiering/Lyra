import AppKit
import Foundation

/// Tracks every open note editor (all tabs in all vault windows) so quit can flush dirty buffers.
@MainActor
final class AppSession {
    static let shared = AppSession()

    /// Only the first vault window restores the last-opened bookmark.
    private(set) var didRestoreLaunchVault = false
    /// Folders chosen for newly created windows, keyed by the window that
    /// should consume them. A FIFO list would let a later window bind to the
    /// wrong pick if scene creation order differs from enqueue order.
    private var pendingVaultHandoff = PendingVaultHandoff()

    private struct Entry {
        // Keep a failed editor alive across an unexpected scene teardown so a
        // cancelled quit can retry the save instead of losing its buffer.
        // The store is also retained for a failed editor so its security scope
        // is not released before a retry.
        var editor: EditorViewModel?
        var store: VaultStore?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// Returns true once — used by `VaultStore` init so only one window auto-opens the last vault.
    func claimLaunchVaultRestore() -> Bool {
        if didRestoreLaunchVault { return false }
        didRestoreLaunchVault = true
        return true
    }

    @discardableResult
    func setPendingVaultURL(_ url: URL) -> UUID {
        pendingVaultHandoff.enqueue(url)
    }

    func takePendingVaultURL(for id: UUID) -> URL? {
        pendingVaultHandoff.take(id)
    }

    func discardPendingVaultURL(for id: UUID) {
        pendingVaultHandoff.discard(id)
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

/// One-shot vault URL handoff from the window that picked a folder to the
/// window created for that pick. Tokens are not reusable.
struct PendingVaultHandoff: Equatable {
    private var pending: [UUID: URL] = [:]

    @discardableResult
    mutating func enqueue(_ url: URL) -> UUID {
        let id = UUID()
        pending[id] = url
        return id
    }

    mutating func take(_ id: UUID) -> URL? {
        pending.removeValue(forKey: id)
    }

    mutating func discard(_ id: UUID) {
        pending.removeValue(forKey: id)
    }

    var isEmpty: Bool { pending.isEmpty }
}
