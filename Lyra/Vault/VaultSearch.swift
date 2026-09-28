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

    // MARK: - Go to File

    /// A note offered by Go to File.
    struct NoteEntry: Equatable, Sendable {
        var url: URL
        /// Vault-relative path including `.md` (`Essays/On Slow Writing.md`).
        var relativePath: String

        /// Filename without `.md`: the note's name.
        var name: String {
            ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        }

        /// Folders above the note (`Essays`), empty at the vault root.
        var folder: String {
            (relativePath as NSString).deletingLastPathComponent
        }
    }

    /// Notes for Go to File, best match first, at most `limit`.
    ///
    /// An empty query lists notes by path. Otherwise matching ignores case
    /// and ranks, best first: the exact name, a name prefix, a word in the
    /// name, anywhere in the name, every word of the query in the name, the
    /// path, and finally the query's letters in order (`osw` finds
    /// "On Slow Writing"). Ties go to the shorter name, then the path.
    static func rankNotes(_ notes: [NoteEntry], query: String, limit: Int = 200) -> [NoteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            let sorted = notes.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            return Array(sorted.prefix(max(0, limit)))
        }
        let words = q.split(whereSeparator: \.isWhitespace).map(String.init)
        let scored: [(entry: NoteEntry, score: Int, name: String)] = notes.compactMap { entry in
            let name = entry.name
            guard let score = matchScore(name: name.lowercased(), path: entry.relativePath.lowercased(), query: q, words: words) else {
                return nil
            }
            return (entry, score, name)
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
            return lhs.entry.relativePath.localizedStandardCompare(rhs.entry.relativePath) == .orderedAscending
        }
        return sorted.prefix(max(0, limit)).map(\.entry)
    }

    /// Higher is better; `nil` when the note does not match.
    static func matchScore(name: String, path: String, query: String, words: [String]) -> Int? {
        if name == query { return 1000 }
        if name.hasPrefix(query) { return 900 }
        if let range = name.range(of: query) {
            let before = name[..<range.lowerBound].last
            let startsWord = before.map { !$0.isLetter && !$0.isNumber } ?? true
            return startsWord ? 800 : 700
        }
        if words.count > 1, words.allSatisfy({ name.contains($0) }) { return 600 }
        if path.contains(query) { return 500 }
        if words.count > 1, words.allSatisfy({ path.contains($0) }) { return 400 }
        if isSubsequence(query, of: name) { return 300 }
        if isSubsequence(query, of: path) { return 100 }
        return nil
    }

    /// Whether every non-space character of `needle` appears in `haystack` in order.
    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle.filter { !$0.isWhitespace }[...]
        guard !remaining.isEmpty else { return false }
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return false
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
        FileSystemVault.relativePath(for: node.url, under: vaultRoot)
    }
}
