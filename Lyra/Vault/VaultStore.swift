import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private static let bookmarkKey = "lyra.lastVaultBookmark"
    private static let destinationGone = "The destination is no longer available inside this vault."
    private static let folderGone = "The selected folder is no longer available inside this vault."
    private static let cannotCreateFile = "Lyra couldn't create a new Markdown file in this folder."
    private static let nameTaken = "A file with that name already exists."

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
    /// Every node of `rootNode` by id, so selection lookups do not walk the tree.
    private var nodesByID: [VaultNode.ID: VaultNode] = [:]
    /// Every note with its vault-relative path, for Go to File. Read on demand,
    /// never from a view body, so it is not observed.
    @ObservationIgnored private(set) var noteEntries: [VaultSearch.NoteEntry] = []
    /// Indexed note bodies from the last scan with the stamp they were read at.
    /// A rescan (every window activation) re-reads only notes that changed.
    /// In memory only; disk stays the source of truth.
    private var bodyCache: [String: FileSystemVault.CachedBody] = [:]
    /// True when scan stopped walking folders deeper than `FileSystemVault.maxDirectoryDepth`.
    private(set) var scanDidTruncate = false
    /// True when at least one note was too large to index for search/backlinks.
    private(set) var scanSkippedLargeNotes = false
    /// True when at least one note could not be read or decoded as UTF-8.
    private(set) var scanSkippedUnreadableNotes = false
    /// Resolved bookmark that macOS marked stale. Open only after the user confirms.
    private(set) var staleRestoreURL: URL?
    /// Bumped each time a scan lands, so views can recompute derived data
    /// (backlinks) when the index changes without comparing trees.
    private(set) var indexVersion = 0
    /// Bookmark for the open vault, so the window can remember its own folder.
    private(set) var rootBookmark: Data?
    /// Drops stale async scan results when a newer refresh was requested.
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?

    init() {}

    func present(error: Error, context: UserFacingError.Context) {
        let pair = UserFacingError.presentable(for: error, context: context)
        errorTitle = pair.title
        errorMessage = pair.message
    }

    /// Pre-built body (include tips yourself, or use `present(_:detail:)`).
    func present(context: UserFacingError.Context, message: String) {
        errorTitle = context.title
        errorMessage = message
    }

    /// `detail` explains what went wrong; the context adds its usual tip.
    func present(_ context: UserFacingError.Context, detail: String) {
        present(context: context, message: UserFacingError.message(context: context, detail: detail))
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
        lastCreateParentPath = nil
        clearScan()
        refresh()
    }

    /// Forget the tree, indexes, and selection until the next scan lands.
    private func clearScan() {
        rootNode = nil
        nodesByID = [:]
        noteEntries = []
        bodyCache = [:]
        selection = nil
        pendingSelection = nil
        wikiResolver = WikiLinkResolver()
        searchDocuments = []
        scanDidTruncate = false
        scanSkippedLargeNotes = false
        scanSkippedUnreadableNotes = false
    }

    /// Scan the vault off the main actor so large trees don't beachball the UI.
    ///
    /// Rescans are cheap when little changed: unchanged note bodies come from
    /// `bodyCache`, the wiki and search indexes are rebuilt only when the tree
    /// or a body changed, and observed properties are assigned only when their
    /// value differs, so the sidebar and backlinks do not redraw for nothing.
    func refresh() {
        guard let rootURL else { return }
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let url = rootURL
        let previous = ScanBaseline(
            tree: rootNode,
            cache: bodyCache,
            index: rootNode == nil ? nil : ScanIndex(resolver: wikiResolver, documents: searchDocuments)
        )
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
                    try Self.scan(root: url, previous: previous)
                }
                let output = try await withTaskCancellationHandler(
                    operation: { try await scanTask.value },
                    onCancel: { scanTask.cancel() }
                )
                try Task.checkCancellation()
                guard let self, generation == self.refreshGeneration else { return }
                self.apply(output)
            } catch {
                guard let self, generation == self.refreshGeneration else { return }
                if error is CancellationError { return }
                self.clearScan()
                self.present(error: error, context: .readVault)
            }
        }
    }

    /// Index state a rescan compares against.
    private struct ScanBaseline: Sendable {
        var tree: VaultNode?
        var cache: [String: FileSystemVault.CachedBody]
        var index: ScanIndex?
    }

    private struct ScanIndex: Sendable {
        var resolver: WikiLinkResolver
        var documents: [VaultFullTextSearch.Document]
    }

    private struct ScanOutput: Sendable {
        var tree: VaultNode
        /// `nil` when the tree matches the previous scan.
        var nodesByID: [VaultNode.ID: VaultNode]?
        /// `nil` when the tree matches the previous scan.
        var noteEntries: [VaultSearch.NoteEntry]?
        /// `nil` when neither the tree nor any note body changed.
        var index: ScanIndex?
        var cache: [String: FileSystemVault.CachedBody]
        var didTruncate: Bool
        var skippedLarge: Bool
        var skippedUnreadable: Bool
    }

    /// Walks the tree and indexes note bodies. Runs off the main actor.
    private nonisolated static func scan(root url: URL, previous: ScanBaseline) throws -> ScanOutput {
        let scanned = try FileSystemVault.scanResult(root: url, shouldCancel: { Task.isCancelled })
        let treeChanged = scanned.node != previous.tree
        var cache: [String: FileSystemVault.CachedBody] = [:]
        var entries: [(url: URL, relativePath: String, body: FileSystemVault.IndexedBody)] = []
        var bodiesChanged = false
        var skippedLarge = false
        var skippedUnreadable = false
        for noteURL in FileSystemVault.collectNoteURLs(from: scanned.node) {
            if Task.isCancelled { throw CancellationError() }
            let read = FileSystemVault.indexedBody(at: noteURL, cached: previous.cache[noteURL.path])
            if read.didRead { bodiesChanged = true }
            if let stamp = read.stamp {
                cache[noteURL.path] = FileSystemVault.CachedBody(stamp: stamp, body: read.body)
            }
            switch read.body {
            case .body: break
            case .oversized: skippedLarge = true
            case .unreadable: skippedUnreadable = true
            }
            entries.append((noteURL, FileSystemVault.relativePath(for: noteURL, under: url), read.body))
        }

        // Nothing moved and no body changed: keep the current indexes.
        var index: ScanIndex?
        if previous.index == nil || treeChanged || bodiesChanged {
            var notes: [WikiNote] = []
            var documents: [VaultFullTextSearch.Document] = []
            var urlBodies: [URL: String] = [:]
            for entry in entries {
                if Task.isCancelled { throw CancellationError() }
                guard case .body(let body) = entry.body else {
                    // Still a note: `[[links]]` to it must resolve, not offer Create.
                    notes.append(WikiNote(url: entry.url, relativePath: entry.relativePath, aliases: []))
                    continue
                }
                notes.append(
                    WikiNote(
                        url: entry.url,
                        relativePath: entry.relativePath,
                        aliases: FrontmatterAliases.parse(from: body)
                    )
                )
                documents.append(
                    VaultFullTextSearch.Document(url: entry.url, relativePath: entry.relativePath, body: body)
                )
                urlBodies[entry.url] = body
            }
            index = ScanIndex(resolver: WikiLinkResolver(notes: notes, bodies: urlBodies), documents: documents)
        }
        return ScanOutput(
            tree: scanned.node,
            nodesByID: treeChanged ? FileSystemVault.nodesByID(in: scanned.node) : nil,
            noteEntries: treeChanged
                ? entries.map { VaultSearch.NoteEntry(url: $0.url, relativePath: $0.relativePath) }
                : nil,
            index: index,
            cache: cache,
            didTruncate: scanned.didTruncate,
            skippedLarge: skippedLarge,
            skippedUnreadable: skippedUnreadable
        )
    }

    private func apply(_ output: ScanOutput) {
        bodyCache = output.cache
        if let nodes = output.nodesByID {
            rootNode = output.tree
            nodesByID = nodes
        }
        if let notes = output.noteEntries {
            noteEntries = notes
        }
        if let index = output.index {
            wikiResolver = index.resolver
            searchDocuments = index.documents
            indexVersion += 1
        }
        if scanDidTruncate != output.didTruncate { scanDidTruncate = output.didTruncate }
        if scanSkippedLargeNotes != output.skippedLarge { scanSkippedLargeNotes = output.skippedLarge }
        if scanSkippedUnreadableNotes != output.skippedUnreadable {
            scanSkippedUnreadableNotes = output.skippedUnreadable
        }
        // Apply pending selection only after the tree contains the new path.
        if let pending = pendingSelection {
            if nodesByID[pending] != nil {
                selection = pending
            }
            pendingSelection = nil
        }
        // External deletes/renames must not leave a selection pointing nowhere.
        if let selection, nodesByID[selection] == nil {
            self.selection = nil
        }
    }

    func selectedNode() -> VaultNode? {
        guard let selection else { return nil }
        return nodesByID[selection]
    }

    /// The node with `id` (its path) in the current tree.
    func node(withID id: VaultNode.ID) -> VaultNode? {
        nodesByID[id]
    }

    func selectedFileURL() -> URL? {
        guard let node = selectedNode(), !node.isDirectory else { return nil }
        return node.url
    }

    func resolveWikiLink(_ text: String) -> WikiResolveResult {
        wikiResolver.resolve(text)
    }

    /// The resolver from the last scan. Captured before a rename so links
    /// to the old name can still be found afterwards.
    var linkResolver: WikiLinkResolver { wikiResolver }

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

    /// Scanned note bodies with open editors' text laid over them. Sendable,
    /// so a caller can run `VaultFullTextSearch.search` off the main actor.
    func searchCorpus(liveBodies: [String: String]) -> [VaultFullTextSearch.Document] {
        guard !liveBodies.isEmpty else { return searchDocuments }
        return searchDocuments.map { doc in
            var copy = doc
            if let live = liveBodies[doc.url.path] {
                copy.body = live
            }
            return copy
        }
    }

    /// Creates a note at an explicit vault path (wiki Create). Intermediate folders are created.
    @discardableResult
    func createNote(at dest: URL) -> Bool {
        guard let rootURL else { return false }
        guard dest.pathExtension.lowercased() == "md" else {
            present(.createNote, detail: "New notes must be Markdown files.")
            return false
        }
        guard FileSystemVault.isWithin(dest, root: rootURL),
              !FileSystemVault.hasSymlink(dest, relativeTo: rootURL) else {
            present(.createNote, detail: "The destination is not inside this vault.")
            return false
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            guard FileSystemVault.isSafePath(dest, within: rootURL),
                  FileSystemVault.isRegularFile(dest) else {
                present(.createNote, detail: "Something at that destination already exists and is not a Markdown note.")
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
            present(.createNote, detail: Self.destinationGone)
            return false
        }
        guard FileSystemVault.exclusivelyCreateEmptyFile(at: dest) else {
            if FileManager.default.fileExists(atPath: dest.path) {
                return createNote(at: dest)
            }
            present(.createNote, detail: Self.cannotCreateFile)
            return false
        }
        // Post-create boundary check. Do not remove the file here: if the
        // parent was swapped off-vault, removal could delete outside the vault.
        guard FileSystemVault.isSafePath(dest, within: rootURL) else {
            present(.createNote, detail: Self.destinationGone)
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
            present(.createNote, detail: Self.folderGone)
            return false
        }
        var fileName = ""
        // The untitled loop creates its file exclusively; a named note is created below.
        var alreadyCreated = false
        if let rawName {
            switch FilenameValidation.validate(rawName, isDirectory: false) {
            case .invalid(let detail):
                present(.createNote, detail: detail)
                return false
            case .ok(let name):
                let dest = parent.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: dest.path) {
                    present(.createNote, detail: Self.nameTaken)
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
                    alreadyCreated = true
                    break
                }
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    present(.createNote, detail: Self.cannotCreateFile)
                    return false
                }
            }
            guard fileName != "" else {
                present(.createNote, detail: Self.cannotCreateFile)
                return false
            }
        }
        let url = parent.appendingPathComponent(fileName)
        guard alreadyCreated || FileSystemVault.isSafePath(url, within: rootURL) else {
            present(.createNote, detail: Self.destinationGone)
            return false
        }
        // Named creation already rejected collisions. Exclusive creation closes
        // the remaining check-then-create race; a failure with an existing file
        // is reported as a collision.
        guard alreadyCreated || FileSystemVault.exclusivelyCreateEmptyFile(at: url) else {
            if FileManager.default.fileExists(atPath: url.path) {
                present(.createNote, detail: Self.nameTaken)
            } else {
                present(.createNote, detail: Self.cannotCreateFile)
            }
            return false
        }
        // Post-create vault-boundary check. Do not remove the file here: if the
        // parent moved off-vault, removal could delete outside the vault.
        guard FileSystemVault.isSafePath(url, within: rootURL) else {
            present(.createNote, detail: Self.destinationGone)
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
            present(.createFolder, detail: Self.folderGone)
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
                present(.createFolder, detail: Self.folderGone)
                return
            }
            lastCreateParentPath = parent.path
            pendingSelection = url.path
            refresh()
        } catch {
            present(error: error, context: .createFolder)
        }
    }

    /// Vault-relative folder that New Note and New Folder create in; empty
    /// for the vault root. Shown in the New Note sheet.
    func newItemFolderPath() -> String {
        guard let rootURL else { return "" }
        let parent = createParentDirectory(vaultRoot: rootURL)
        guard FileSystemVault.isStrictDescendant(parent, root: rootURL) else { return "" }
        return FileSystemVault.relativePath(for: parent, under: rootURL)
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

    /// Renames the tree item at `url` without touching the sidebar selection first,
    /// so callers do not trigger a selection-driven open of the old path.
    @discardableResult
    func renameItem(at url: URL, to newName: String) -> URL? {
        rename(nodesByID[url.path], to: newName)
    }

    private func rename(_ node: VaultNode?, to newName: String) -> URL? {
        guard let rootURL, let node,
              FileSystemVault.isStrictDescendant(node.url, root: rootURL) else {
            present(
                context: .rename,
                message: "The selected item is no longer available inside this vault. Refresh and try again."
            )
            return nil
        }
        switch FilenameValidation.validate(newName, isDirectory: node.isDirectory) {
        case .invalid(let detail):
            present(.rename, detail: detail)
            return nil
        case .ok(let name):
            let dest = node.url.deletingLastPathComponent().appendingPathComponent(name)
            // `Note` for `Note.md` validates back to the same name; moving onto itself fails.
            if dest.path == node.url.path {
                return dest
            }
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
                try FileSystemVault.move(node.url, to: dest)
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

    /// Launch restore for a window with no remembered folder of its own:
    /// reopen the most recently opened vault.
    func restoreLastVault() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        restoreVault(fromBookmark: data)
    }

    /// Reopen a vault from a security-scoped bookmark (the window's own, or
    /// the last-opened one). A stale bookmark asks the user first.
    func restoreVault(fromBookmark data: Data) {
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
            rootBookmark = bookmark
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
