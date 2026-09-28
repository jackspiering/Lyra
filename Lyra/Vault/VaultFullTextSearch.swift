import Foundation

/// In-memory body search. Rebuilt from the last vault scan (plus live buffers).
enum VaultFullTextSearch {
    struct Hit: Equatable, Identifiable, Sendable {
        var url: URL
        var relativePath: String
        var snippet: String
        var id: String { url.path }
    }

    struct Document: Equatable, Sendable {
        var url: URL
        var relativePath: String
        var body: String
    }

    /// Upper bound on palette rows; a one-letter query should not list the vault.
    static let defaultLimit = 200

    /// Case-insensitive substring match on path or body. Empty query returns no hits.
    /// Sorted by path, then capped at `limit`.
    static func search(documents: [Document], query: String, limit: Int = defaultLimit) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return [] }
        var hits: [Hit] = []
        for doc in documents {
            let pathHit = doc.relativePath.range(of: q, options: .caseInsensitive) != nil
            let snippet = Self.snippet(in: doc.body, query: q)
            if snippet == nil && !pathHit { continue }
            hits.append(
                Hit(
                    url: doc.url,
                    relativePath: doc.relativePath,
                    snippet: snippet ?? doc.relativePath
                )
            )
        }
        hits.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return Array(hits.prefix(max(0, limit)))
    }

    static func snippet(in text: String, query: String, radius: Int = 42) -> String? {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var slice = String(text[start..<end])
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        while slice.contains("  ") {
            slice = slice.replacingOccurrences(of: "  ", with: " ")
        }
        slice = slice.trimmingCharacters(in: .whitespaces)
        if start != text.startIndex { slice = "…" + slice }
        if end != text.endIndex { slice += "…" }
        return slice
    }
}
