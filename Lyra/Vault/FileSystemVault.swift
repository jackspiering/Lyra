import Foundation

enum FileSystemVault {
    static func shouldInclude(name: String) -> Bool {
        if name.hasPrefix(".") { return false }
        return true
    }

    static func scan(root: URL) throws -> VaultNode {
        let name = root.lastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if !isDir.boolValue {
            return VaultNode(name: name, url: root, isDirectory: false, children: nil)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
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
                children.append(try scan(root: childURL))
            } else if childURL.pathExtension.lowercased() == "md" {
                children.append(
                    VaultNode(name: childName, url: childURL, isDirectory: false, children: nil)
                )
            }
        }

        children.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return VaultNode(name: name, url: root, isDirectory: true, children: children)
    }

    static func collectNoteURLs(from node: VaultNode) -> [URL] {
        if !node.isDirectory {
            return node.url.pathExtension.lowercased() == "md" ? [node.url] : []
        }
        return (node.children ?? []).flatMap(collectNoteURLs(from:))
    }

    static func parentDirectory(for selection: VaultNode?, vaultRoot: URL) -> URL {
        guard let selection else { return vaultRoot }
        if selection.isDirectory { return selection.url }
        return selection.url.deletingLastPathComponent()
    }

    static func findNode(id: String, in node: VaultNode) -> VaultNode? {
        if node.id == id { return node }
        for child in node.children ?? [] {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}
