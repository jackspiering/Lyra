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
    private var wikiResolver = WikiLinkResolver()
    private var searchDocuments: [VaultFullTextSearch.Document] = []
    /// True when scan stopped walking folders deeper than `FileSystemVault.maxDirectoryDepth`.
    private(set) var scanDidTruncate = false
    /// True when at least one note was too large to index for search/backlinks.
    private(set) var scanSkippedLargeNotes = false
    /// True when at least one note could not be read or decoded as UTF-8.
    private(set) var scanSkippedUnreadableNotes = false
    /// Resolved bookmark that macOS marked stale. Open only after the user confirms.
    private(set) var staleRestoreURL: URL?
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

    var needsStaleVaultConfirmation: Bool { staleRestoreURL != nil }

    func confirmStaleVaultRestore() {
        guard let url = staleRestoreURL else { return }
        staleRestoreURL = nil
        openVault(at: url)
    }

    func declineStaleVaultRestore() {
        staleRestoreURL = nil
    }

    func replaceStaleVaultRestore(with url: URL) {
        staleRestoreURL = nil
        openVault(at: url)
    }

    func openVault(at url: URL) {
        staleRestoreURL = nil
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

        refreshTask?.cancel()
        stopAccessingIfNeeded()
        isAccessingSecurityScope = startedAccess
        persistBookmark(for: url)
        rootURL = url
        AppSession.shared.updateVaultRoot(for: self, root: url)
        pendingSelection = nil
        lastCreateParentPath = nil
        selection = nil
        rootNode = nil
        scanDidTruncate = false
        scanSkippedLargeNotes = false
        scanSkippedUnreadableNotes = false
        refresh()
    }

    /// Scan the vault off the main actor so large trees don't beachball the UI.
    func refresh() {
        guard let rootURL else { return }
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let url = rootURL
        // Retain security-scoped access for this scan. The task is cancelled
        // before scopes change, but file I/O cannot be cancelled mid-read.
        let retainedScanAccess = isAccessingSecurityScope
            ? url.startAccessingSecurityScopedResource()
            : false
        refreshTask = Task { [weak self] in
            defer {
                if retainedScanAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let scanTask = Task.detached(priority: .userInitiated) {
                    let scanned = try FileSystemVault.scanResult(
                        root: url,
                        shouldCancel: { Task.isCancelled }
                    )
                    let noteURLs = FileSystemVault.collectNoteURLs(from: scanned.node)
                    var notes: [WikiNote] = []
                    var documents: [VaultFullTextSearch.Document] = []
                    var urlBodies: [URL: String] = [:]
                    var skippedLarge = false
                    var skippedUnreadable = false
                    for noteURL in noteURLs {
                        if Task.isCancelled { throw CancellationError() }
                        switch FileSystemVault.indexedUTF8Body(at: noteURL) {
                        case .body(let body):
                            let relative = FileSystemVault.relativePath(for: noteURL, under: url)
                            notes.append(
                                WikiNote(
                                    url: noteURL,
                                    relativePath: relative,
                                    aliases: FrontmatterAliases.parse(from: body)
                                )
                            )
                            documents.append(
                                VaultFullTextSearch.Document(
                                    url: noteURL,
                                    relativePath: relative,
                                    body: body
                                )
                            )
                            urlBodies[noteURL] = body
                        case .oversized:
                            skippedLarge = true
                        case .unreadable:
                            skippedUnreadable = true
                        }
                    }
                    let resolver = WikiLinkResolver(notes: notes, bodies: urlBodies)
                    return (scanned.node, resolver, documents, scanned.didTruncate, skippedLarge, skippedUnreadable)
                }
                let (node, resolver, documents, didTruncate, skippedLarge, skippedUnreadable) = try await withTaskCancellationHandler(
                    operation: { try await scanTask.value },
                    onCancel: { scanTask.cancel() }
                )
                try Task.checkCancellation()
                guard let self, generation == self.refreshGeneration else { return }
                self.rootNode = node
                self.wikiResolver = resolver
                self.searchDocuments = documents
                self.scanDidTruncate = didTruncate
                self.scanSkippedLargeNotes = skippedLarge
                self.scanSkippedUnreadableNotes = skippedUnreadable
                // Apply pending selection only after the tree contains the new path.
                if let pending = self.pendingSelection {
                    if FileSystemVault.findNode(id: pending, in: node) != nil {
                        self.selection = pending
                    }
                    self.pendingSelection = nil
                }
                // External deletes/renames must not leave a selection pointing nowhere.
                if let selection = self.selection,
                   FileSystemVault.findNode(id: selection, in: node) == nil {
                    self.selection = nil
                }
            } catch {
                guard let self, generation == self.refreshGeneration else { return }
                if error is CancellationError { return }
                self.rootNode = nil
                self.selection = nil
                self.pendingSelection = nil
                self.wikiResolver = WikiLinkResolver()
                self.searchDocuments = []
                self.scanDidTruncate = false
                self.scanSkippedLargeNotes = false
                self.scanSkippedUnreadableNotes = false
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

    func resolveWikiLink(_ text: String) -> WikiResolveResult {
        wikiResolver.resolve(text)
    }

    func backlinks(to url: URL, liveBodies: [String: String]) -> [Backlink] {
        var live: [URL: String] = [:]
        for doc in searchDocuments {
            if let body = liveBodies[doc.url.path] {
                live[doc.url] = body
            }
        }
        return wikiResolver.backlinks(to: url, liveBodies: live).map { candidate in
            let body = live[candidate.url]
                ?? searchDocuments.first(where: { $0.url == candidate.url })?.body
            return Backlink(
                url: candidate.url,
                relativePath: candidate.relativePath,
                context: body.flatMap { wikiResolver.backlinkContext(in: $0, to: url) }
            )
        }
    }

    func searchNoteBodies(query: String, liveBodies: [String: String]) -> [VaultFullTextSearch.Hit] {
        let documents = searchDocuments.map { doc in
            var copy = doc
            if let live = liveBodies[doc.url.path] {
                copy.body = live
            }
            return copy
        }
        return VaultFullTextSearch.search(documents: documents, query: query)
    }

    /// Creates a note at an explicit vault path (wiki Create). Intermediate folders are created.
    @discardableResult
    func createNote(at dest: URL) -> Bool {
        guard let rootURL else { return false }
        guard dest.pathExtension.lowercased() == "md" else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "New notes must be Markdown files."
                )
            )
            return false
        }
        guard FileSystemVault.isWithin(dest, root: rootURL),
              !FileSystemVault.hasSymlink(dest, relativeTo: rootURL) else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "The destination is not inside this vault."
                )
            )
            return false
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            guard FileSystemVault.isSafePath(dest, within: rootURL),
                  FileSystemVault.isRegularFile(dest),
                  dest.pathExtension.lowercased() == "md" else {
                present(
                    context: .createNote,
                    message: UserFacingError.message(
                        context: .createNote,
                        detail: "Something at that destination already exists and is not a Markdown note."
                    )
                )
                return false
            }
            pendingSelection = dest.path
            refresh()
            return true
        }
        let parent = dest.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            present(error: error, context: .createNote)
            return false
        }
        guard FileSystemVault.isSafeDirectory(parent, within: rootURL) else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "The destination is no longer available inside this vault."
                )
            )
            return false
        }
        guard FileSystemVault.exclusivelyCreateEmptyFile(at: dest) else {
            if FileManager.default.fileExists(atPath: dest.path) {
                return createNote(at: dest)
            }
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "Lyra couldn't create a new Markdown file in this folder."
                )
            )
            return false
        }
        // Post-create boundary check. Do not remove the file here: if the
        // parent was swapped off-vault, removal could delete outside the vault.
        guard FileSystemVault.isSafePath(dest, within: rootURL) else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "The destination is no longer available inside this vault."
                )
            )
            return false
        }
        lastCreateParentPath = parent.path
        pendingSelection = dest.path
        refresh()
        return true
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
        var fileName = ""
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
            for _ in 0..<100 {
                let candidate = parent.appendingPathComponent(
                    UntitledName.next(base: stem, ext: "md", in: parent)
                )
                guard FileSystemVault.isSafePath(candidate, within: rootURL) else {
                    continue
                }
                if FileSystemVault.exclusivelyCreateEmptyFile(at: candidate) {
                    fileName = candidate.lastPathComponent
                    break
                }
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    present(
                        context: .createNote,
                        message: UserFacingError.message(
                            context: .createNote,
                            detail: "Lyra couldn't create a new Markdown file in this folder."
                        )
                    )
                    return false
                }
            }
            guard fileName != "" else {
                present(
                    context: .createNote,
                    message: UserFacingError.message(
                        context: .createNote,
                        detail: "Lyra couldn't create a new Markdown file in this folder."
                    )
                )
                return false
            }
        }
        let url = parent.appendingPathComponent(fileName)
        guard FileSystemVault.isSafePath(url, within: rootURL) else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "The destination is no longer available inside this vault."
                )
            )
            return false
        }
        // Named creation already rejected collisions. Exclusive creation closes
        // the remaining check-then-create race; a failure with an existing file
        // is reported as a collision.
        guard FileSystemVault.exclusivelyCreateEmptyFile(at: url) else {
            if FileManager.default.fileExists(atPath: url.path) {
                present(
                    context: .createNote,
                    message: UserFacingError.message(
                        context: .createNote,
                        detail: "A file with that name already exists."
                    )
                )
            } else {
                present(
                    context: .createNote,
                    message: UserFacingError.message(
                        context: .createNote,
                        detail: "Lyra couldn't create a new Markdown file in this folder."
                    )
                )
            }
            return false
        }
        // Post-create vault-boundary check. Do not remove the file here: if the
        // parent moved off-vault, removal could delete outside the vault.
        guard FileSystemVault.isSafePath(url, within: rootURL) else {
            present(
                context: .createNote,
                message: UserFacingError.message(
                    context: .createNote,
                    detail: "The destination is no longer available inside this vault."
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
            // Post-create check for TOCTOU on the new folder and its parent.
            // Only clean up when the resolved path is still inside the vault.
            guard FileSystemVault.isSafePath(url, within: rootURL),
                  FileSystemVault.isSafeDirectory(parent, within: rootURL) else {
                if FileSystemVault.isWithin(url, root: rootURL) {
                    try? FileManager.default.removeItem(at: url)
                }
                present(
                    context: .createFolder,
                    message: UserFacingError.message(
                        context: .createFolder,
                        detail: "The selected folder is no longer available inside this vault."
                    )
                )
                return
            }
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
              FileSystemVault.isStrictDescendant(node.url, root: rootURL) else {
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

    @discardableResult
    func deleteSelected() -> Bool {
        guard let rootURL, let node = selectedNode() else { return false }
        guard FileSystemVault.isStrictDescendant(node.url, root: rootURL) else {
            present(
                context: .delete,
                message: "The selected item is no longer available inside this vault. Refresh and try again."
            )
            return false
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
            return true
        } catch {
            present(error: error, context: .delete)
            return false
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
        let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        switch VaultBookmarkRestore.decision(didResolve: url != nil, isStale: isStale) {
        case .skip:
            return
        case .promptUser:
            // Do not auto-open or re-persist. The window asks the user first.
            staleRestoreURL = url
        case .autoOpen:
            if let url {
                openVault(at: url)
            }
        }
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
