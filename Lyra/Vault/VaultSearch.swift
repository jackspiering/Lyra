import Foundation

/// Name/path filter for the sidebar vault tree (not full-text content search).
enum VaultSearch {
    /// Case-insensitive: node name or path contains query. Empty (or whitespace-only) query → match all.
    static func matches(nodeName: String, path: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return nodeName.range(of: q, options: .caseInsensitive) != nil
            || path.range(of: q, options: .caseInsensitive) != nil
    }

    /// Prunes non-matching leaves while keeping ancestors of matches so folder structure remains.
    /// Empty query returns `root` unchanged. When nothing matches, returns root with empty children.
    static func filteredTree(root: VaultNode, query: String) -> VaultNode {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return root }
        if let filtered = filterNode(root, query: q, vaultRoot: root.url) {
            return filtered
        }
        return VaultNode(
            name: root.name,
            url: root.url,
            isDirectory: root.isDirectory,
            children: root.isDirectory ? [] : nil
        )
    }

    // MARK: - Private

    private static func filterNode(_ node: VaultNode, query: String, vaultRoot: URL) -> VaultNode? {
        let path = relativePath(for: node, vaultRoot: vaultRoot)
        let selfMatches = matches(nodeName: node.name, path: path, query: query)

        if !node.isDirectory {
            return selfMatches ? node : nil
        }

        let filteredChildren = (node.children ?? []).compactMap {
            filterNode($0, query: query, vaultRoot: vaultRoot)
        }

        // Keep folder if its name/path matches or any descendant survived pruning.
        guard selfMatches || !filteredChildren.isEmpty else { return nil }

        return VaultNode(
            name: node.name,
            url: node.url,
            isDirectory: true,
            children: filteredChildren
        )
    }

    private static func relativePath(for node: VaultNode, vaultRoot: URL) -> String {
        let rootPath = vaultRoot.standardizedFileURL.path
        let nodePath = node.url.standardizedFileURL.path
        guard nodePath.hasPrefix(rootPath) else { return node.name }
        var rest = String(nodePath.dropFirst(rootPath.count))
        if rest.hasPrefix("/") {
            rest = String(rest.dropFirst())
        }
        return rest.isEmpty ? node.name : rest
    }
}
