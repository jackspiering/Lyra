import Foundation

/// Parse, extract, and locate `[[wiki]]` destinations. Shared by resolve, backlinks, and Source click.
enum WikiLinkSyntax {
    struct Match: Equatable {
        var range: NSRange
        var inner: String
        var target: String
    }

    /// Split `path|alias` (or a bare path). Strips a trailing `.md` from the target.
    static func parseInner(_ inner: String) -> (target: String, display: String?) {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTarget: String
        let display: String?
        if let pipe = trimmed.firstIndex(of: "|") {
            rawTarget = String(trimmed[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
            let label = String(trimmed[trimmed.index(after: pipe)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            display = label.isEmpty ? nil : label
        } else {
            rawTarget = trimmed
            display = nil
        }
        return (normalizeTarget(rawTarget), display)
    }

    /// Forward slashes, no trailing `.md`, no leading/trailing slashes.
    static func normalizeTarget(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "\\", with: "/")
        while name.hasPrefix("/") { name.removeFirst() }
        while name.hasSuffix("/") { name.removeLast() }
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3))
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vault-relative path including `.md` (`Projects/Roadmap.md`).
    static func relativePath(for url: URL, vaultRoot: URL) -> String {
        FileSystemVault.relativePath(for: url, under: vaultRoot)
    }

    /// Lowercased relative path without `.md`.
    static func relativeKey(forRelativePath path: String) -> String {
        normalizeTarget(path).lowercased()
    }

    /// Filename stem, lowercased (`roadmap` for `Projects/Roadmap.md`).
    static func stemKey(forRelativePath path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return normalizeTarget(name).lowercased()
    }

    /// Where Create should write the file. `nil` if the target is empty or unsafe.
    static func destinationURL(target: String, vaultRoot: URL, linkingNoteURL: URL?) -> URL? {
        let normalized = normalizeTarget(target)
        guard !normalized.isEmpty else { return nil }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return nil }

        var url = parts.count == 1
            ? (linkingNoteURL?.deletingLastPathComponent() ?? vaultRoot)
            : vaultRoot

        if parts.count > 1 {
            for folder in parts.dropLast() {
                switch FilenameValidation.validate(folder, isDirectory: true) {
                case .invalid:
                    return nil
                case .ok(let name):
                    url.appendPathComponent(name)
                }
            }
        }

        switch FilenameValidation.validate(parts[parts.count - 1], isDirectory: false) {
        case .invalid:
            return nil
        case .ok(let name):
            url.appendPathComponent(name)
        }

        guard FileSystemVault.isWithin(url, root: vaultRoot),
              !FileSystemVault.hasSymlink(url, relativeTo: vaultRoot) else { return nil }
        return url
    }

    /// `[[…]]` matches outside fenced code and inline code. Ranges are UTF-16 for `NSTextView`.
    static func extractLinks(in markdown: String) -> [Match] {
        let ns = markdown as NSString
        let full = NSRange(location: 0, length: ns.length)
        let skipped = skippedRanges(in: ns)
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        return regex.matches(in: markdown, range: full).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let outer = match.range
            if skipped.contains(where: { NSIntersectionRange($0, outer).length > 0 }) {
                return nil
            }
            // `![[...]]` embeds are explicitly unsupported: do not treat the
            // inner brackets as a normal wiki link.
            if outer.location > 0, ns.character(at: outer.location - 1) == 0x21 {
                return nil
            }
            let inner = ns.substring(with: match.range(at: 1))
            let target = parseInner(inner).target
            // `[[Note#heading]]` fragments are explicitly unsupported.
            guard !target.isEmpty, !target.contains("#") else { return nil }
            return Match(range: outer, inner: inner, target: target)
        }
    }

    static func link(atUTF16Offset offset: Int, in markdown: String) -> Match? {
        extractLinks(in: markdown).first { NSLocationInRange(offset, $0.range) }
    }

    // MARK: - Skip code

    private static func skippedRanges(in ns: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        ranges.append(contentsOf: fencedCodeRanges(in: ns))
        ranges.append(contentsOf: inlineCodeRanges(in: ns, excluding: ranges))
        return ranges
    }

    /// Fenced code ranges for callers such as Source highlighting. Heading
    /// fragments are not supported, so links containing `#` are left alone.
    static func fencedCodeRanges(in markdown: String) -> [NSRange] {
        fencedCodeRanges(in: markdown as NSString)
    }

    static func fencedCodeRanges(in ns: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var i = 0
        let length = ns.length
        var fence: (marker: UInt16, run: Int)?
        var fenceStart = 0
        while i < length {
            let lineStart = i
            while i < length {
                let ch = ns.character(at: i)
                if ch == 0x0A || ch == 0x0D { break }
                i += 1
            }
            let line = ns.substring(with: NSRange(location: lineStart, length: i - lineStart))
            if let open = fence {
                if isClosingFence(line, marker: open.marker, run: open.run) {
                    var end = i
                    if i < length {
                        let ch = ns.character(at: i)
                        if ch == 0x0D {
                            end += 1
                            if end < length && ns.character(at: end) == 0x0A { end += 1 }
                        } else if ch == 0x0A {
                            end += 1
                        }
                    }
                    ranges.append(NSRange(location: fenceStart, length: end - fenceStart))
                    fence = nil
                    i = end
                    continue
                }
            } else if let parsed = openingFence(line) {
                fence = parsed
                fenceStart = lineStart
            }
            if i < length {
                let ch = ns.character(at: i)
                if ch == 0x0D {
                    i += 1
                    if i < length && ns.character(at: i) == 0x0A { i += 1 }
                } else if ch == 0x0A {
                    i += 1
                }
            }
        }
        if fence != nil {
            ranges.append(NSRange(location: fenceStart, length: length - fenceStart))
        }
        return ranges
    }

    private static func openingFence(_ raw: String) -> (marker: UInt16, run: Int)? {
        var index = raw.startIndex
        var indentation = 0
        while index < raw.endIndex, (raw[index] == " " || raw[index] == "\t"), indentation < 4 {
            indentation += raw[index] == "\t" ? 4 : 1
            index = raw.index(after: index)
        }
        guard indentation <= 3, index < raw.endIndex else { return nil }
        let markerChar = raw[index]
        guard markerChar == "`" || markerChar == "~" else { return nil }
        let runStart = index
        while index < raw.endIndex, raw[index] == markerChar {
            index = raw.index(after: index)
        }
        let run = raw.distance(from: runStart, to: index)
        guard run >= 3 else { return nil }
        if markerChar == "`", raw[index...].contains("`") { return nil }
        let utf = String(markerChar).utf16
        guard let unit = utf.first else { return nil }
        return (unit, run)
    }

    private static func isClosingFence(_ raw: String, marker: UInt16, run: Int) -> Bool {
        guard let scalar = UnicodeScalar(UInt32(marker)) else { return false }
        let markerString = String(scalar)
        var index = raw.startIndex
        var indentation = 0
        while index < raw.endIndex, (raw[index] == " " || raw[index] == "\t"), indentation < 4 {
            indentation += raw[index] == "\t" ? 4 : 1
            index = raw.index(after: index)
        }
        guard indentation <= 3, index < raw.endIndex, String(raw[index]) == markerString else {
            return false
        }
        let runStart = index
        while index < raw.endIndex, String(raw[index]) == markerString {
            index = raw.index(after: index)
        }
        let length = raw.distance(from: runStart, to: index)
        guard length >= run else { return false }
        return raw[index...].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func inlineCodeRanges(in ns: NSString, excluding fences: [NSRange]) -> [NSRange] {
        let source = ns as String
        var ranges: [NSRange] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard source[cursor] == "`" else {
                cursor = source.index(after: cursor)
                continue
            }
            let openingStart = cursor
            var openingEnd = cursor
            while openingEnd < source.endIndex, source[openingEnd] == "`" {
                openingEnd = source.index(after: openingEnd)
            }
            let length = source.distance(from: openingStart, to: openingEnd)
            guard let closing = closingBacktickRun(in: source, after: openingEnd, length: length) else {
                cursor = openingEnd
                continue
            }
            let nsRange = NSRange(openingStart..<closing.upperBound, in: source)
            if !fences.contains(where: { NSIntersectionRange($0, nsRange).length > 0 }) {
                ranges.append(nsRange)
            }
            cursor = closing.upperBound
        }
        return ranges
    }

    private static func closingBacktickRun(
        in source: String,
        after start: String.Index,
        length: Int
    ) -> Range<String.Index>? {
        var index = start
        while index < source.endIndex {
            guard source[index] == "`" else {
                index = source.index(after: index)
                continue
            }
            let runStart = index
            var runEnd = index
            while runEnd < source.endIndex, source[runEnd] == "`" {
                runEnd = source.index(after: runEnd)
            }
            if source.distance(from: runStart, to: runEnd) == length {
                return runStart..<runEnd
            }
            index = runEnd
        }
        return nil
    }
}
