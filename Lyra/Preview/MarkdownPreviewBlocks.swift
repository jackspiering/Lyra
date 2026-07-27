import Foundation

/// Lightweight Markdown block split for the native preview (no WebKit).
enum MarkdownPreviewBlocks {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(String)
        case quote(String)
        case code(String)
        case thematicBreak
        case image(alt: String, path: String)
    }

    /// A block plus its UTF-16 range in the original source (for Live Preview splice).
    struct RangedBlock: Equatable {
        var block: Block
        /// UTF-16 range in the source string (`NSString` indices).
        var range: NSRange
    }

    static func parse(_ source: String) -> [Block] {
        parseRanged(source).map(\.block)
    }

    static func parseRanged(_ source: String) -> [RangedBlock] {
        var blocks: [RangedBlock] = []
        let lines = splitLines(source)
        var i = 0
        var paragraphIndices: [Int] = []

        func flushParagraph() {
            guard let first = paragraphIndices.first, let last = paragraphIndices.last else { return }
            let texts = paragraphIndices.map { lines[$0].text }
            let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphIndices.removeAll()
            guard !text.isEmpty else { return }
            let start = lines[first].start
            let end = lines[last].end
            let range = NSRange(location: start, length: end - start)
            if let image = MarkdownImagePath.parseImageLine(text) {
                blocks.append(RangedBlock(block: .image(alt: image.alt, path: image.path), range: range))
            } else {
                blocks.append(RangedBlock(block: .paragraph(text), range: range))
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let openStart = line.start
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i].text)
                    i += 1
                }
                let closeEnd: Int
                if i < lines.count {
                    closeEnd = lines[i].end
                    i += 1
                } else {
                    closeEnd = lines[max(0, i - 1)].end
                }
                let range = NSRange(location: openStart, length: closeEnd - openStart)
                blocks.append(RangedBlock(block: .code(code.joined(separator: "\n")), range: range))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                let range = NSRange(location: line.start, length: line.end - line.start)
                blocks.append(RangedBlock(block: .thematicBreak, range: range))
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                let range = NSRange(location: line.start, length: line.end - line.start)
                blocks.append(RangedBlock(block: heading, range: range))
                i += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                let body = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                let range = NSRange(location: line.start, length: line.end - line.start)
                blocks.append(RangedBlock(block: .quote(body), range: range))
                i += 1
                continue
            }

            if let item = parseListItem(trimmed) {
                flushParagraph()
                let range = NSRange(location: line.start, length: line.end - line.start)
                blocks.append(RangedBlock(block: .listItem(item), range: range))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraphIndices.append(i)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    /// Replace a UTF-16 range in `source` with `replacement`.
    static func replacing(in source: String, range: NSRange, with replacement: String) -> String {
        let ns = source as NSString
        guard range.location != NSNotFound,
              range.location >= 0,
              range.location + range.length <= ns.length else { return source }
        return ns.replacingCharacters(in: range, with: replacement)
    }

    /// Protect `[[wiki]]` from CommonMark link parsing, then render inline markdown.
    static func prepareInlineMarkdown(_ source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return source }
        let ns = source as NSString
        var result = source
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let name = ns.substring(with: match.range(at: 1))
            let replacement = "**⟦\(name)⟧**"
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    // MARK: - Line split (UTF-16 offsets)

    private struct Line {
        let text: String
        let start: Int
        var end: Int { start + (text as NSString).length }
    }

    private static func splitLines(_ source: String) -> [Line] {
        let ns = source as NSString
        var lines: [Line] = []
        var i = 0
        while i < ns.length {
            let start = i
            while i < ns.length {
                let ch = ns.character(at: i)
                if ch == 0x0A || ch == 0x0D { break }
                i += 1
            }
            let len = i - start
            lines.append(Line(text: ns.substring(with: NSRange(location: start, length: len)), start: start))
            if i < ns.length {
                let ch = ns.character(at: i)
                if ch == 0x0D {
                    i += 1
                    if i < ns.length && ns.character(at: i) == 0x0A { i += 1 }
                } else if ch == 0x0A {
                    i += 1
                }
            }
        }
        return lines
    }

    private static func parseHeading(_ trimmed: String) -> Block? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level), trimmed.count > level else { return nil }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard trimmed[idx].isWhitespace else { return nil }
        let text = trimmed[trimmed.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    private static func parseListItem(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return String(trimmed.dropFirst(2))
        }
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\.\s+(.*)$"#) else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
