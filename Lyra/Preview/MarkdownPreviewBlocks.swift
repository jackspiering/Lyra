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

    static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                paragraph.removeAll()
                return
            }
            if let image = MarkdownImagePath.parseImageLine(text) {
                blocks.append(.image(alt: image.alt, path: image.path))
            } else {
                blocks.append(.paragraph(text))
            }
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
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

            if let item = parseListItem(trimmed) {
                flushParagraph()
                blocks.append(.listItem(item))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraph.append(line)
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
