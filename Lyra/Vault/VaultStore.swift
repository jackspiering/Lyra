import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private static let bookmarkKey = "lyra.lastVaultBookmark"

    var rootURL: URL?
    var rootNode: VaultNode?
    var selection: VaultNode.ID?
    var errorMessage: String?
    private var isAccessingSecurityScope = false
    private var wikiResolver = WikiLinkResolver(noteURLs: [])

    init() {
        restoreLastVaultIfPossible()
    }

    func openVault(at url: URL) {
        stopAccessingIfNeeded()
        errorMessage = nil
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            errorMessage = "Could not save vault bookmark: \(error.localizedDescription)"
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
            errorMessage = error.localizedDescription
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
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() {
        guard let node = selectedNode() else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            selection = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
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
