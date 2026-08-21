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
    /// Target file path → notes that uniquely `[[wiki]]` to it. Built once per scan.
    private let backlinksByTargetPath: [String: [WikiCandidate]]

    init(notes: [WikiNote] = [], bodies: [URL: String] = [:]) {
        self.notes = notes
        self.backlinksByTargetPath = bodies.isEmpty
            ? [:]
            : Self.makeBacklinkIndex(notes: notes, bodies: bodies)
    }

    init(noteURLs: [URL], vaultRoot: URL, aliases: [URL: [String]] = [:], bodies: [URL: String] = [:]) {
        let notes = noteURLs.map { url in
            WikiNote(
                url: url,
                relativePath: WikiLinkSyntax.relativePath(for: url, vaultRoot: vaultRoot),
                aliases: aliases[url] ?? []
            )
        }
        self.init(notes: notes, bodies: bodies)
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
    ///
    /// `liveBodies` overlays open-editor text onto the scan-time index so the
    /// inspector stays current for notes being typed, without walking every
    /// vault body on each frame.
    func backlinks(to targetURL: URL, liveBodies: [URL: String] = [:]) -> [WikiCandidate] {
        if backlinksByTargetPath.isEmpty, !liveBodies.isEmpty {
            return WikiLinkResolver(notes: notes, bodies: liveBodies).backlinks(to: targetURL)
        }
        var bySource: [String: WikiCandidate] = [:]
        for candidate in backlinksByTargetPath[targetURL.path] ?? [] {
            bySource[candidate.url.path] = candidate
        }
        for (sourceURL, body) in liveBodies {
            bySource.removeValue(forKey: sourceURL.path)
            guard sourceURL != targetURL else { continue }
            let hits = WikiLinkSyntax.extractLinks(in: body).contains { match in
                if case .unique(let url) = resolve(match.target) {
                    return url == targetURL
                }
                return false
            }
            if hits, let note = notes.first(where: { $0.url == sourceURL }) {
                bySource[sourceURL.path] = WikiCandidate(url: note.url, relativePath: note.relativePath)
            }
        }
        return bySource.values.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private static func makeBacklinkIndex(
        notes: [WikiNote],
        bodies: [URL: String]
    ) -> [String: [WikiCandidate]] {
        let resolver = WikiLinkResolver(notes: notes)
        var index: [String: [WikiCandidate]] = [:]
        for note in notes {
            let body = bodies[note.url] ?? ""
            var seen: Set<String> = []
            for match in WikiLinkSyntax.extractLinks(in: body) {
                guard case .unique(let url) = resolver.resolve(match.target), url != note.url else {
                    continue
                }
                let key = url.path
                guard seen.insert(key).inserted else { continue }
                index[key, default: []].append(
                    WikiCandidate(url: note.url, relativePath: note.relativePath)
                )
            }
        }
        for key in index.keys {
            index[key]?.sort {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        }
        return index
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
