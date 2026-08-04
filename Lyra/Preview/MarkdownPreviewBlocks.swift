import Foundation

/// Lightweight Markdown block split for the native preview (no WebKit).
enum MarkdownPreviewBlocks {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        /// `ordinal` is nil for bullets; present for ordered lists. `depth` is leading-spaces/2 (preview heuristic).
        case listItem(text: String, ordinal: Int?, depth: Int)
        case quote(String)
        case code(String)
        case thematicBreak
        case image(alt: String, path: String)
    }

    static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        let lines = splitLines(source)
        var i = 0
        var paragraphIndices: [Int] = []

        func flushParagraph() {
            guard !paragraphIndices.isEmpty else { return }
            let texts = paragraphIndices.map { lines[$0].text }
            let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphIndices.removeAll()
            guard !text.isEmpty else { return }
            if let image = MarkdownImagePath.parseImageLine(text) {
                blocks.append(.image(alt: image.alt, path: image.path))
            } else {
                blocks.append(.paragraph(text))
            }
        }

        while i < lines.count {
            let line = lines[i]
            let raw = line.text
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i].text)
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                let body = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                blocks.append(.quote(body))
                i += 1
                continue
            }

            if let item = parseListItem(raw: raw, trimmed: trimmed) {
                flushParagraph()
                blocks.append(item)
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

    /// Preview-grade list parse. Depth is leading spaces÷2 (tabs count as 2); not full CommonMark.
    private static func parseListItem(raw: String, trimmed: String) -> Block? {
        var leading = 0
        for ch in raw {
            if ch == " " { leading += 1 }
            else if ch == "\t" { leading += 2 }
            else { break }
        }
        let depth = leading / 2

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .listItem(text: String(trimmed.dropFirst(2)), ordinal: nil, depth: depth)
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#) else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 2 else { return nil }
        let ordinal = Int(ns.substring(with: match.range(at: 1)))
        let text = ns.substring(with: match.range(at: 2))
        return .listItem(text: text, ordinal: ordinal, depth: depth)
    }
}
