import Foundation

/// Resolve Markdown image paths and parse image-only lines for preview / PDF.
enum MarkdownImagePath {
    /// Absolute path if the file exists; else note-relative if present; else vault-relative if present; else `nil`.
    static func resolve(path: String, noteDirectory: URL, vaultRoot: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = absoluteFileURL(from: trimmed) {
            return FileManager.default.fileExists(atPath: absolute.path) ? absolute : nil
        }

        // `appending(path:)` keeps multi-segment relatives (e.g. `_attachments/a.png`).
        let noteURL = noteDirectory.appending(path: trimmed)
        if FileManager.default.fileExists(atPath: noteURL.path) {
            return noteURL
        }

        let vaultURL = vaultRoot.appending(path: trimmed)
        if FileManager.default.fileExists(atPath: vaultURL.path) {
            return vaultURL
        }

        return nil
    }

    /// Match a full line of the form `![alt](path)`.
    static func parseImageLine(_ trimmed: String) -> (alt: String, path: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#) else {
            return nil
        }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 3 else {
            return nil
        }
        let alt = ns.substring(with: match.range(at: 1))
        let path = ns.substring(with: match.range(at: 2))
        return (alt, path)
    }

    private static func absoluteFileURL(from path: String) -> URL? {
        guard (path as NSString).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: path)
    }
}
