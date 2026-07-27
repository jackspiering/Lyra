import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private static let bookmarkKey = "lyra.lastVaultBookmark"

    var rootURL: URL?
    var rootNode: VaultNode?
    var selection: VaultNode.ID?
    var noteURLs: [URL] = []
    var errorMessage: String?
    var isAccessingSecurityScope = false

    private var wikiResolver = WikiLinkResolver(noteURLs: [])

    init() {
        restoreLastVaultIfPossible()
    }

    func openVault(at url: URL) async {
        stopAccessingIfNeeded()
        errorMessage = nil

        let accessed = url.startAccessingSecurityScopedResource()
        isAccessingSecurityScope = accessed

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            // Still open for this session even if bookmark fails.
            errorMessage = "Could not save vault bookmark: \(error.localizedDescription)"
        }

        rootURL = url
        await refresh()
    }

    func refresh() async {
        guard let rootURL else { return }
        do {
            let node = try await Task.detached {
                try FileSystemVault.scan(root: rootURL)
            }.value
            rootNode = node
            noteURLs = FileSystemVault.collectNoteURLs(from: node)
            wikiResolver = WikiLinkResolver(noteURLs: noteURLs)
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

    func openNote(url: URL) {
        selection = url.path
    }

    func createNote() async {
        guard let rootURL else { return }
        let parent = FileSystemVault.parentDirectory(for: selectedNode(), vaultRoot: rootURL)
        let name = UntitledName.next(in: parent)
        do {
            let url = try FileSystemVault.createNote(named: name, in: parent)
            await refresh()
            selection = url.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder() async {
        guard let rootURL else { return }
        let parent = FileSystemVault.parentDirectory(for: selectedNode(), vaultRoot: rootURL)
        let base = "New Folder"
        var name = base
        var n = 2
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            name = "\(base) \(n)"
            n += 1
        }
        do {
            let url = try FileSystemVault.createFolder(named: name, in: parent)
            await refresh()
            selection = url.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameSelected(to newName: String) async {
        guard let node = selectedNode() else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let newURL = try FileSystemVault.rename(url: node.url, to: trimmed)
            await refresh()
            selection = newURL.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() async {
        guard let node = selectedNode() else { return }
        do {
            try FileSystemVault.trash(node.url)
            selection = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreLastVaultIfPossible() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            Task { await openVault(at: url) }
        } catch {
            // Ignore stale bookmarks at launch.
        }
    }

    private func stopAccessingIfNeeded() {
        if isAccessingSecurityScope, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }
    }
}
