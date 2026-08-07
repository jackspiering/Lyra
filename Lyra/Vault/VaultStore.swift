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
    private var refreshTask: Task<Void, Never>?

    init() {
        // Multi-window: only the first store restores the last vault bookmark.
        if AppSession.shared.claimLaunchVaultRestore() {
            restoreLastVaultIfPossible()
        }
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
        clearError()

        let startedAccess = url.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        let isUsable = url.isFileURL
            && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !FileSystemVault.hasSymlink(url)
            && FileManager.default.isReadableFile(atPath: url.path)
        guard isUsable else {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
            present(
                context: .readVault,
                message: "Choose a readable folder for the vault. The current vault is still open."
            )
            return
        }

        stopAccessingIfNeeded()
        refreshTask?.cancel()
        isAccessingSecurityScope = startedAccess
        persistBookmark(for: url)
        rootURL = url
        AppSession.shared.updateVaultRoot(for: self, root: url)
        pendingSelection = nil
        lastCreateParentPath = nil
        selection = nil
        rootNode = nil
        refresh()
    }

    /// Scan the vault off the main actor so large trees don't beachball the UI.
    func refresh() {
        guard let rootURL else { return }
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let url = rootURL
        refreshTask = Task { [weak self] in
            do {
                let scanTask = Task.detached(priority: .userInitiated) {
                    try FileSystemVault.scan(root: url, shouldCancel: { Task.isCancelled })
                }
                let node = try await withTaskCancellationHandler(
                    operation: { try await scanTask.value },
                    onCancel: { scanTask.cancel() }
                )
                try Task.checkCancellation()
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
                if error is CancellationError { return }
                self.rootNode = nil
                self.selection = nil
                self.pendingSelection = nil
                self.wikiResolver = WikiLinkResolver(noteURLs: [])
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

    /// Creates a note. `nil` name uses `UntitledName.next` with the preferred stem.
    /// Named create validates and rejects collisions. Returns `true` on success.
    @discardableResult
    func createNote(named rawName: String? = nil) -> Bool {
        guard let rootURL else { return false }
        let parent = createParentDirectory(vaultRoot: rootURL)
        guard FileSystemVault.isSafeDirectory(parent, within: rootURL) else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "The selected folder is no longer available inside this vault."
                )
            )
            return false
        }
        let fileName: String
        if let rawName {
            switch FilenameValidation.validate(rawName, isDirectory: false) {
            case .invalid(let detail):
                present(
                    context: .createNote,
                    message: UserFacingError.message(context: .createNote, detail: detail)
                )
                return false
            case .ok(let name):
                let dest = parent.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: dest.path) {
                    present(
                        context: .createNote,
                        message: UserFacingError.message(
                            context: .createNote,
                            detail: "A file with that name already exists."
                        )
                    )
                    return false
                }
                fileName = name
            }
        } else {
            let stem = GeneralPreferences.defaultNoteStem
            fileName = UntitledName.next(base: stem, ext: "md", in: parent)
        }
        let url = parent.appendingPathComponent(fileName)
        let ok = FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        if !ok {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "Lyra couldn't create a new Markdown file in this folder."
                )
            )
            return false
        }
        lastCreateParentPath = parent.path
        pendingSelection = url.path
        refresh()
        return true
    }

    func createFolder() {
        guard let rootURL else { return }
        let parent = createParentDirectory(vaultRoot: rootURL)
        guard FileSystemVault.isSafeDirectory(parent, within: rootURL) else {
            present(
                context: .createFolder,
                message: UserFacingError.message(
                    context: .createFolder,
                    detail: "The selected folder is no longer available inside this vault."
                )
            )
            return
        }
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

    /// Parent for new notes/folders. A current selection always wins; the
    /// remembered path is only a fallback while a refresh is still landing.
    private func createParentDirectory(vaultRoot: URL) -> URL {
        if let selected = selectedNode() {
            return FileSystemVault.parentDirectory(for: selected, vaultRoot: vaultRoot)
        }
        if let path = lastCreateParentPath {
            var isDir: ObjCBool = false
            let remembered = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
               isDir.boolValue,
               FileSystemVault.isSafeDirectory(remembered, within: vaultRoot) {
                return remembered
            }
        }
        return FileSystemVault.parentDirectory(for: selectedNode(), vaultRoot: vaultRoot)
    }

    /// Renames the selected node. Returns the destination URL immediately (usable before
    /// the async tree refresh lands).
    @discardableResult
    func renameSelected(to newName: String) -> URL? {
        guard let rootURL, let node = selectedNode(),
              FileSystemVault.isSafePath(node.url, within: rootURL) else {
            present(
                context: .rename,
                message: "The selected item is no longer available inside this vault. Refresh and try again."
            )
            return nil
        }
        switch Self.validatedRename(newName, isDirectory: node.isDirectory) {
        case .invalid(let detail):
            present(
                context: .rename,
                message: UserFacingError.message(context: .rename, detail: detail)
            )
            return nil
        case .ok(let name):
            let dest = node.url.deletingLastPathComponent().appendingPathComponent(name)
            guard FileSystemVault.isSafeDirectory(
                node.url.deletingLastPathComponent(),
                within: rootURL
            ), FileSystemVault.isSafePath(dest, within: rootURL) else {
                present(
                    context: .rename,
                    message: "The destination is no longer available inside this vault. Refresh and try again."
                )
                return nil
            }
            do {
                try FileManager.default.moveItem(at: node.url, to: dest)
                // Keep create-parent coherent if we renamed the folder we last created into.
                if let last = lastCreateParentPath {
                    if last == node.url.path {
                        lastCreateParentPath = dest.path
                    } else if last.hasPrefix(node.url.path + "/") {
                        lastCreateParentPath = dest.path + String(last.dropFirst(node.url.path.count))
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

    /// Pure rename rules for notes/folders. Used by sidebar rename and unit tests.
    nonisolated static func validatedRename(_ newName: String, isDirectory: Bool) -> FilenameValidation.Result {
        FilenameValidation.validate(newName, isDirectory: isDirectory)
    }

    func deleteSelected() {
        guard let rootURL, let node = selectedNode() else { return }
        guard FileSystemVault.isSafePath(node.url, within: rootURL) else {
            present(
                context: .delete,
                message: "The selected item is no longer available inside this vault. Refresh and try again."
            )
            return
        }
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
        refreshTask?.cancel()
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
