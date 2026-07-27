import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private static let bookmarkKey = "lyra.lastVaultBookmark"

    var rootURL: URL?
    var rootNode: VaultNode?
    var selection: VaultNode.ID?
    /// Alert title (short).
    var errorTitle: String?
    /// Alert body (plain language).
    var errorMessage: String?
    private var isAccessingSecurityScope = false
    private var wikiResolver = WikiLinkResolver(noteURLs: [])

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

        rootURL = url
        refresh()
    }

    func refresh() {
        guard let rootURL else { return }
        do {
            let node = try FileSystemVault.scan(root: rootURL)
            rootNode = node
            wikiResolver = WikiLinkResolver(noteURLs: FileSystemVault.collectNoteURLs(from: node))
        } catch {
            present(error: error, context: .readVault)
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
        let parent = FileSystemVault.parentDirectory(for: selectedNode(), vaultRoot: rootURL)
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
        refresh()
        selection = url.path
    }

    func createFolder() {
        guard let rootURL else { return }
        let parent = FileSystemVault.parentDirectory(for: selectedNode(), vaultRoot: rootURL)
        let url = parent.appendingPathComponent(UntitledName.next(base: "New Folder", ext: nil, in: parent))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            refresh()
            selection = url.path
        } catch {
            present(error: error, context: .createFolder)
        }
    }

    func renameSelected(to newName: String) {
        guard let node = selectedNode() else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dest = node.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: node.url, to: dest)
            refresh()
            selection = dest.path
        } catch {
            present(error: error, context: .rename)
        }
    }

    func deleteSelected() {
        guard let node = selectedNode() else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            selection = nil
            refresh()
        } catch {
            present(error: error, context: .delete)
        }
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
        openVault(at: url)
    }

    private func stopAccessingIfNeeded() {
        if isAccessingSecurityScope, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }
    }
}
