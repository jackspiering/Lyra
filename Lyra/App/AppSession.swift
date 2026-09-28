import AppKit
import Foundation

/// Tracks every open note editor (all tabs in all vault windows) so quit can flush dirty buffers.
@MainActor
final class AppSession {
    static let shared = AppSession()

    /// Only one window per launch reopens the last-opened vault; a window
    /// that restores its own remembered folder also counts.
    private(set) var didRestoreLaunchVault = false
    /// Stores whose window has closed. Their failed editors are orphaned:
    /// no window is left to show recovery for them.
    private var closedStores: Set<ObjectIdentifier> = []
    /// Folders chosen for newly created windows, keyed by the window that
    /// should consume them. A FIFO list would let a later window bind to the
    /// wrong pick if scene creation order differs from enqueue order.
    private var pendingVaultHandoff = PendingVaultHandoff()

    private struct Entry {
        // Keep a failed editor alive across an unexpected scene teardown so a
        // cancelled quit can retry the save instead of losing its buffer.
        // The store is also retained for a failed editor so its security scope
        // is not released before a retry.
        var editor: EditorViewModel
        var store: VaultStore
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// Returns true once, so only one window auto-opens the last vault.
    func claimLaunchVaultRestore() -> Bool {
        if didRestoreLaunchVault { return false }
        didRestoreLaunchVault = true
        return true
    }

    /// A window reopened its own remembered vault; no window should also
    /// reopen the last-opened one.
    func markLaunchVaultRestored() {
        didRestoreLaunchVault = true
    }

    /// The window owning `store` closed.
    func windowClosed(store: VaultStore) {
        closedStores.insert(ObjectIdentifier(store))
    }

    /// Failed editors whose window has closed.
    func orphaned(_ editors: [EditorViewModel]) -> [EditorViewModel] {
        editors.filter { editor in
            guard let entry = entries[ObjectIdentifier(editor)] else { return true }
            return closedStores.contains(ObjectIdentifier(entry.store))
        }
    }

    /// Drop editors the user chose to discard at quit.
    func discard(_ editors: [EditorViewModel]) {
        for editor in editors {
            unregister(editor: editor)
        }
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
    }

    func updateVaultRoot(for store: VaultStore, root: URL?) {
        for entry in entries.values where entry.store === store {
            entry.editor.vaultRoot = root
        }
    }

    func unregister(editor: EditorViewModel) {
        entries.removeValue(forKey: ObjectIdentifier(editor))
    }

    /// Returns editors that blocked save (conflict / missing / I/O).
    @discardableResult
    func saveAllEditors() -> [EditorViewModel] {
        entries.values.map(\.editor).filter { !$0.saveIfNeeded() }
    }

    func releaseAllVaultAccess() {
        for entry in entries.values {
            entry.store.releaseAccess()
        }
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
