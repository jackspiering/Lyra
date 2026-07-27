import Foundation

enum FileSystemVault {
    static func shouldInclude(name: String) -> Bool {
        if name == ".DS_Store" || name == ".git" { return false }
        if name.hasPrefix(".") { return false }
        return true
    }

    static func scan(root: URL) throws -> VaultNode {
        try scanNode(at: root)
    }

    private static func scanNode(at url: URL) throws -> VaultNode {
        let name = url.lastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if !isDir.boolValue {
            return VaultNode(name: name, url: url, isDirectory: false, children: nil)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        )

        var children: [VaultNode] = []
        for childURL in contents {
            let childName = childURL.lastPathComponent
            guard shouldInclude(name: childName) else { continue }

            let values = try childURL.resourceValues(forKeys: [.isDirectoryKey])
            let childIsDir = values.isDirectory ?? false

            if childIsDir {
                children.append(try scanNode(at: childURL))
            } else if childURL.pathExtension.lowercased() == "md" {
                children.append(
                    VaultNode(name: childName, url: childURL, isDirectory: false, children: nil)
                )
            }
        }

        children.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return VaultNode(name: name, url: url, isDirectory: true, children: children)
    }

    /// Flatten all markdown file URLs under a tree node.
    static func collectNoteURLs(from node: VaultNode) -> [URL] {
        var result: [URL] = []
        if !node.isDirectory {
            if node.url.pathExtension.lowercased() == "md" {
                result.append(node.url)
            }
            return result
        }
        for child in node.children ?? [] {
            result.append(contentsOf: collectNoteURLs(from: child))
        }
        return result
    }

    static func readUTF8(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func writeUTF8(_ string: String, to url: URL) throws {
        try string.write(to: url, atomically: true, encoding: .utf8)
    }

    static func createNote(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }

    static func createFolder(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func rename(url: URL, to newName: String) throws -> URL {
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    static func trash(_ url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    /// Parent directory for new items given the current selection.
    static func parentDirectory(for selection: VaultNode?, vaultRoot: URL) -> URL {
        guard let selection else { return vaultRoot }
        if selection.isDirectory { return selection.url }
        return selection.url.deletingLastPathComponent()
    }

    /// Find a node by path id in the tree.
    static func findNode(id: String, in node: VaultNode) -> VaultNode? {
        if node.id == id { return node }
        for child in node.children ?? [] {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}
