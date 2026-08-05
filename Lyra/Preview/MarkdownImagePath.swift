import Foundation

/// Resolve Markdown image paths and parse image-only lines for preview / PDF.
enum MarkdownImagePath {
    /// Absolute path if the file exists; else note-relative if present; else vault-relative
    /// (when not `../…`); else basename under `vaultRoot/_attachments`. Percent-encoded
    /// destinations are decoded before lookup. Returned URLs are standardized.
    static func resolve(path: String, noteDirectory: URL, vaultRoot: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let decoded = trimmed.removingPercentEncoding ?? trimmed

        if let absolute = absoluteFileURL(from: decoded) {
            return exists(absolute)
        }

        // `appending(path:)` keeps multi-segment relatives; standardize so `..` is resolved.
        let noteURL = noteDirectory.appending(path: decoded).standardizedFileURL
        if let hit = exists(noteURL) { return hit }

        // Only use vault-relative when path does not start with `../` (avoids escaping vault).
        if !decoded.hasPrefix("..") {
            let vaultURL = vaultRoot.appending(path: decoded).standardizedFileURL
            if let hit = exists(vaultURL) { return hit }
        }

        // Obsidian/Lyra: any …/_attachments/file.ext → vaultRoot/_attachments/file.ext
        if let name = attachmentsBasename(from: decoded) {
            let candidate = vaultRoot
                .appendingPathComponent(AttachmentStore.folderName, isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL
            if let hit = exists(candidate) { return hit }
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

    private static func exists(_ url: URL) -> URL? {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    /// Match `_attachments/<file>` segment anywhere in the relative path.
    private static func attachmentsBasename(from path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(of: AttachmentStore.folderName),
              idx + 1 < parts.count else { return nil }
        let name = parts[idx + 1]
        guard !name.isEmpty, name != "..", name != "." else { return nil }
        return name
    }
}
