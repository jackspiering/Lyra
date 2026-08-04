import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private static let bookmarkKey = "lyra.lastVaultBookmark"

    var rootURL: URL?
    var rootNode: VaultNode?
    var selection: VaultNode.ID?
    /// Applied after the next successful scan lands (so the tree contains the new path).
    private var pendingSelection: String?
    /// Parent directory used for the last successful create (survives stale tree snapshots).
    private var lastCreateParentPath: String?
    /// Alert title (short).
    var errorTitle: String?
    /// Alert body (plain language).
    var errorMessage: String?
    private var isAccessingSecurityScope = false
    private var wikiResolver = WikiLinkResolver(noteURLs: [])
    /// Drops stale async scan results when a newer refresh was requested.
    private var refreshGeneration = 0

    init() {
        restoreLastVaultIfPossible()
    }

    func present(error: Error, context: UserFacingError.Context) {
        let pair = UserFacingError.presentable(for: error, context: context)
        errorTitle = pair.title
        errorMessage = pair.message
    }

    /// Pre-built body (include tips yourself, or use `UserFacingError.message`).
    func present(context: UserFacingError.Context, message: String) {
        errorTitle = context.title
        errorMessage = message
    }

    func clearError() {
        errorTitle = nil
        errorMessage = nil
    }

    func openVault(at url: URL) {
        stopAccessingIfNeeded()
        clearError()
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        persistBookmark(for: url)
        rootURL = url
        pendingSelection = nil
        lastCreateParentPath = nil
        selection = nil
        rootNode = nil
        refresh()
    }

    /// Scan the vault off the main actor so large trees don't beachball the UI.
    func refresh() {
        guard let rootURL else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let url = rootURL
        Task { [weak self] in
            do {
                let node = try await Task.detached(priority: .userInitiated) {
                    try FileSystemVault.scan(root: url)
                }.value
                guard let self, generation == self.refreshGeneration else { return }
                self.rootNode = node
                self.wikiResolver = WikiLinkResolver(
                    noteURLs: FileSystemVault.collectNoteURLs(from: node)
                )
                // Apply pending selection only after the tree contains the new path.
                if let pending = self.pendingSelection {
                    self.selection = pending
                    self.pendingSelection = nil
                }
            } catch {
                guard let self, generation == self.refreshGeneration else { return }
                self.present(error: error, context: .readVault)
            }
        }
    }

    func selectedNode() -> VaultNode? {
        guard let selection, let rootNode else { return nil }
        return FileSystemVault.findNode(id: selection, in: rootNode)
    }

    func selectedFileURL() -> URL? {
        guard let node = selectedNode(), !node.isDirectory else { return nil }
        return node.url
    }

    func resolveWikiLink(_ text: String) -> URL? {
        wikiResolver.resolve(text)
    }

    func createNote() {
        guard let rootURL else { return }
        let parent = createParentDirectory(vaultRoot: rootURL)
        let url = parent.appendingPathComponent(UntitledName.next(in: parent))
        let ok = FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        if !ok {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "Lyra couldn't create a new Markdown file in this folder."
                )
            )
            return
        }
        lastCreateParentPath = parent.path
        pendingSelection = url.path
        refresh()
    }

    func createFolder() {
        guard let rootURL else { return }
        let parent = createParentDirectory(vaultRoot: rootURL)
        let url = parent.appendingPathComponent(UntitledName.next(base: "New Folder", ext: nil, in: parent))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            lastCreateParentPath = parent.path
            pendingSelection = url.path
            refresh()
        } catch {
            present(error: error, context: .createFolder)
        }
    }

    /// Parent for new notes/folders. Prefers the remembered create parent (avoids race with
    /// async refresh), then the selected node, then the vault root.
    private func createParentDirectory(vaultRoot: URL) -> URL {
        if let path = lastCreateParentPath {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileSystemVault.parentDirectory(for: selectedNode(), vaultRoot: vaultRoot)
    }

    /// Renames the selected node. Returns the destination URL immediately (usable before
    /// the async tree refresh lands).
    @discardableResult
    func renameSelected(to newName: String) -> URL? {
        guard let node = selectedNode() else { return nil }
        switch Self.validatedRename(newName, isDirectory: node.isDirectory) {
        case .invalid(let detail):
            present(
                context: .rename,
                message: UserFacingError.message(context: .rename, detail: detail)
            )
            return nil
        case .ok(let name):
            let dest = node.url.deletingLastPathComponent().appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: node.url, to: dest)
                // Keep create-parent coherent if we renamed the folder we last created into.
                if let last = lastCreateParentPath {
                    if last == node.url.path {
                        lastCreateParentPath = dest.path
                    } else if last.hasPrefix(node.url.path + "/") {
                        lastCreateParentPath = dest.path + last.dropFirst(node.url.path.count)
                    }
                }
                pendingSelection = dest.path
                refresh()
                return dest
            } catch {
                present(error: error, context: .rename)
                return nil
            }
        }
    }

    /// Pure rename rules for notes/folders. Used by the sheet and unit tests.
    enum ValidatedRename: Equatable, Sendable {
        case ok(String)
        case invalid(String)
    }

    nonisolated static func validatedRename(_ newName: String, isDirectory: Bool) -> ValidatedRename {
        var trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid("Name can't be empty.")
        }
        if trimmed.contains("/") || trimmed.contains(":") {
            return .invalid("Names can't contain / or :.")
        }
        if trimmed.hasPrefix(".") {
            return .invalid("Names can't start with a period (they'd be hidden).")
        }
        if trimmed == ".." || trimmed == "." {
            return .invalid("That name isn't valid.")
        }
        if !isDirectory, !trimmed.lowercased().hasSuffix(".md") {
            trimmed += ".md"
        }
        return .ok(trimmed)
    }

    func deleteSelected() {
        guard let node = selectedNode() else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            if let last = lastCreateParentPath,
               last == node.url.path || last.hasPrefix(node.url.path + "/") {
                lastCreateParentPath = nil
            }
            selection = nil
            pendingSelection = nil
            refresh()
        } catch {
            present(error: error, context: .delete)
        }
    }

    /// Balance `startAccessingSecurityScopedResource` (e.g. on quit).
    func releaseAccess() {
        stopAccessingIfNeeded()
    }

    private func restoreLastVaultIfPossible() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        // openVault re-persists the bookmark, including when the resolved one was stale.
        openVault(at: url)
    }

    private func persistBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            present(error: error, context: .rememberVault)
        }
    }

    private func stopAccessingIfNeeded() {
        if isAccessingSecurityScope, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }
    }
}
