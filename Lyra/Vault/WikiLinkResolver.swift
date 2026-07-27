import Foundation

struct WikiLinkResolver {
    private let notesByStem: [String: URL]

    init(noteURLs: [URL]) {
        var map: [String: URL] = [:]
        for url in noteURLs {
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            if map[stem] == nil {
                map[stem] = url
            }
        }
        self.notesByStem = map
    }

    /// Resolves wiki link text (without brackets), e.g. `Note Name` or `Note Name.md`.
    func resolve(_ linkText: String) -> URL? {
        var name = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3))
        }
        return notesByStem[name.lowercased()]
    }
}
