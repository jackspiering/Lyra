import Foundation

/// Resolve Markdown image paths and parse image-only lines for preview / PDF.
enum MarkdownImagePath {
    /// Resolve a local image only when its final, symlink-resolved URL is inside
    /// the vault. Note-relative paths are tried first so `../_attachments/...`
    /// works for notes in nested folders.
    static func resolve(path: String, noteDirectory: URL, vaultRoot: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let root = vaultRoot.resolvingSymlinksInPath().standardizedFileURL

        if let absolute = absoluteFileURL(from: decoded) {
            return exists(absolute, within: root)
        }
        if let fileURL = URL(string: decoded), fileURL.isFileURL {
            return exists(fileURL, within: root)
        }
        // Do not turn remote or custom-scheme destinations into paths below
        // the vault by accident.
        if URL(string: decoded)?.scheme != nil {
            return nil
        }

        // `appending(path:)` keeps multi-segment relatives; standardize so `..` is resolved.
        let noteURL = noteDirectory.appending(path: decoded).standardizedFileURL
        if let hit = exists(noteURL, within: root) { return hit }

        let vaultURL = vaultRoot.appending(path: decoded).standardizedFileURL
        if let hit = exists(vaultURL, within: root) { return hit }

        // Obsidian/Lyra: any …/_attachments/file.ext → vaultRoot/_attachments/file.ext
        if let name = attachmentsBasename(from: decoded) {
            let candidate = vaultRoot
                .appendingPathComponent(AttachmentStore.folderName, isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL
            if let hit = exists(candidate, within: root) { return hit }
        }

        return nil
    }

    /// Match a full line of the form `![alt](path)`.
    static func parseImageLine(_ trimmed: String) -> (alt: String, path: String)? {
        let line = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = line as NSString
        guard ns.length >= 4, ns.hasPrefix("![") else { return nil }

        var cursor = 2
        while cursor < ns.length {
            if ns.character(at: cursor) == 0x5C, cursor + 1 < ns.length {
                cursor += 2
                continue
            }
            if ns.character(at: cursor) == 0x5D { break }
            cursor += 1
        }
        guard cursor < ns.length,
              cursor + 1 < ns.length,
              ns.character(at: cursor + 1) == 0x28 else {
            return nil
        }

        let alt = ns.substring(with: NSRange(location: 2, length: cursor - 2))
        cursor += 2
        while cursor < ns.length, isWhitespace(ns.character(at: cursor)) { cursor += 1 }

        let path: String
        if cursor < ns.length, ns.character(at: cursor) == 0x3C { // `<destination>`
            let start = cursor + 1
            cursor = start
            while cursor < ns.length {
                if ns.character(at: cursor) == 0x5C, cursor + 1 < ns.length {
                    cursor += 2
                    continue
                }
                if ns.character(at: cursor) == 0x3E { break }
                cursor += 1
            }
            guard cursor < ns.length else { return nil }
            path = unescapeDestination(
                ns.substring(with: NSRange(location: start, length: cursor - start))
            )
            cursor += 1
        } else {
            let start = cursor
            var nestedParentheses = 0
            while cursor < ns.length {
                let character = ns.character(at: cursor)
                if character == 0x5C, cursor + 1 < ns.length {
                    cursor += 2
                    continue
                }
                if character == 0x28 {
                    nestedParentheses += 1
                    cursor += 1
                    continue
                }
                if character == 0x29 {
                    if nestedParentheses == 0 { break }
                    nestedParentheses -= 1
                    cursor += 1
                    continue
                }
                if isWhitespace(character), nestedParentheses == 0 { break }
                cursor += 1
            }
            path = unescapeDestination(
                ns.substring(with: NSRange(location: start, length: cursor - start))
            )
        }
        guard !path.isEmpty else { return nil }

        while cursor < ns.length, isWhitespace(ns.character(at: cursor)) { cursor += 1 }
        if cursor < ns.length, ns.character(at: cursor) != 0x29 {
            // Optional title: `"..."`, `'...'`, or `(...)`.
            let opening = ns.character(at: cursor)
            if opening == 0x22 || opening == 0x27 {
                let closing = opening
                cursor += 1
                while cursor < ns.length {
                    if ns.character(at: cursor) == 0x5C, cursor + 1 < ns.length {
                        cursor += 2
                        continue
                    }
                    if ns.character(at: cursor) == closing { break }
                    cursor += 1
                }
                guard cursor < ns.length else { return nil }
                cursor += 1
            } else if opening == 0x28 {
                var depth = 1
                cursor += 1
                while cursor < ns.length, depth > 0 {
                    let character = ns.character(at: cursor)
                    if character == 0x5C, cursor + 1 < ns.length {
                        cursor += 2
                        continue
                    }
                    if character == 0x28 { depth += 1 }
                    if character == 0x29 { depth -= 1 }
                    cursor += 1
                }
                guard depth == 0 else { return nil }
            } else {
                return nil
            }
            while cursor < ns.length, isWhitespace(ns.character(at: cursor)) { cursor += 1 }
        }

        guard cursor < ns.length,
              ns.character(at: cursor) == 0x29,
              cursor + 1 == ns.length else {
            return nil
        }
        return (alt, path)
    }

    private static func absoluteFileURL(from path: String) -> URL? {
        guard (path as NSString).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func exists(_ url: URL, within vaultRoot: URL) -> URL? {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(standardized, root: vaultRoot),
              FileManager.default.fileExists(atPath: standardized.path) else {
            return nil
        }
        return standardized
    }

    private static func isWithin(_ url: URL, root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = url.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy { $0 == $1 }
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09 || character == 0x0A || character == 0x0D
    }

    private static func unescapeDestination(_ path: String) -> String {
        var result = ""
        var index = path.startIndex
        while index < path.endIndex {
            if path[index] == "\\" {
                let next = path.index(after: index)
                if next < path.endIndex {
                    result.append(path[next])
                    index = path.index(after: next)
                    continue
                }
            }
            result.append(path[index])
            index = path.index(after: index)
        }
        return result
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
