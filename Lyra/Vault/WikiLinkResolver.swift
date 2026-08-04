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
        // Exact stem (or full link text treated as stem)
        if let url = notesByStem[name.lowercased()] {
            return url
        }
        // Path-style wiki links e.g. `Daily Notes/2026-07-27` → stem of last component
        if name.contains("/") {
            let last = (name as NSString).lastPathComponent
            return notesByStem[last.lowercased()]
        }
        return nil
    }
}
