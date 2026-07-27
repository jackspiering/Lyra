import Foundation

struct WikiLinkResolver {
    private let notesByStem: [String: URL]

    init(noteURLs: [URL]) {
        notesByStem = noteURLs.reduce(into: [:]) { map, url in
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            if map[stem] == nil { map[stem] = url }
        }
    }

    func resolve(_ linkText: String) -> URL? {
        var name = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3))
        }
        return notesByStem[name.lowercased()]
    }
}
