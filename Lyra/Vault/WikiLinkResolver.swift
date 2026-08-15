import Foundation

struct WikiNote: Equatable, Sendable {
    var url: URL
    var relativePath: String
    var aliases: [String]
}

struct WikiCandidate: Equatable, Identifiable, Sendable {
    var url: URL
    var relativePath: String
    var id: String { url.path }
}

enum WikiResolveResult: Equatable, Sendable {
    case unique(URL)
    case ambiguous([WikiCandidate])
    case unresolved
}

/// Path-aware wiki resolve. A real stem or path beats an alias. Never guesses.
struct WikiLinkResolver: Sendable {
    private let notes: [WikiNote]

    init(notes: [WikiNote] = []) {
        self.notes = notes
    }

    init(noteURLs: [URL], vaultRoot: URL, aliases: [URL: [String]] = [:]) {
        notes = noteURLs.map { url in
            WikiNote(
                url: url,
                relativePath: WikiLinkSyntax.relativePath(for: url, vaultRoot: vaultRoot),
                aliases: aliases[url] ?? []
            )
        }
    }

    func resolve(_ linkText: String) -> WikiResolveResult {
        let target = WikiLinkSyntax.parseInner(linkText).target
        guard !target.isEmpty else { return .unresolved }
        let key = target.lowercased()
        let hasPath = target.contains("/")

        if hasPath {
            let pathHits = notes.filter { note in
                let rel = WikiLinkSyntax.relativeKey(forRelativePath: note.relativePath)
                return rel == key || rel.hasSuffix("/" + key)
            }
            return finish(pathHits)
        }

        let stemHits = notes.filter { WikiLinkSyntax.stemKey(forRelativePath: $0.relativePath) == key }
        if !stemHits.isEmpty {
            return finish(stemHits)
        }

        let aliasHits = notes.filter { note in
            note.aliases.contains { WikiLinkSyntax.normalizeTarget($0).lowercased() == key }
        }
        return finish(aliasHits)
    }

    /// Notes whose `[[wiki]]` uniquely resolve to `targetURL`.
    func backlinks(to targetURL: URL, bodies: [URL: String]) -> [WikiCandidate] {
        var result: [WikiCandidate] = []
        for note in notes {
            guard note.url != targetURL else { continue }
            let body = bodies[note.url] ?? ""
            let links = WikiLinkSyntax.extractLinks(in: body)
            let hits = links.contains { match in
                if case .unique(let url) = resolve(match.target) {
                    return url == targetURL
                }
                return false
            }
            if hits {
                result.append(WikiCandidate(url: note.url, relativePath: note.relativePath))
            }
        }
        result.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return result
    }

    private func finish(_ hits: [WikiNote]) -> WikiResolveResult {
        if hits.isEmpty { return .unresolved }
        if hits.count == 1 { return .unique(hits[0].url) }
        let candidates = hits
            .map { WikiCandidate(url: $0.url, relativePath: $0.relativePath) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return .ambiguous(candidates)
    }
}
