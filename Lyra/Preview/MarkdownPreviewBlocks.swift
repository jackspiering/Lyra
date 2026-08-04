import Foundation

/// Lightweight Markdown block split for the native preview (no WebKit).
enum MarkdownPreviewBlocks {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        /// `ordinal` is nil for bullets; present for ordered lists. `depth` is leading-spaces/2 (preview heuristic).
        /// `taskChecked` is non-nil for GitHub-style task list items (`- [ ]` / `- [x]`).
        case listItem(text: String, ordinal: Int?, depth: Int, taskChecked: Bool?)
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

    /// Turn `[[wiki]]` into markdown links `lyra-wiki:` so Reading can open them as clickable links.
    /// Skips conversion inside inline code spans (`` `...` ``). Supports Obsidian `[[path|alias]]`.
    static func prepareInlineMarkdown(_ source: String) -> String {
        // Split on `...` code spans; only transform segments outside code.
        var result = ""
        var i = source.startIndex
        var inCode = false
        var segmentStart = i
        while i < source.endIndex {
            if source[i] == "`" {
                let segment = String(source[segmentStart..<i])
                result += inCode ? segment : rewriteWikis(in: segment)
                inCode.toggle()
                result.append("`")
                segmentStart = source.index(after: i)
            }
            i = source.index(after: i)
        }
        let tail = String(source[segmentStart...])
        result += inCode ? tail : rewriteWikis(in: tail)
        return result
    }

    /// Rewrite bare `[[…]]` wiki links (not inside code) to markdown `lyra-wiki:` links.
    private static func rewriteWikis(in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return source }
        let ns = source as NSString
        var result = source
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let body = ns.substring(with: match.range(at: 1))
            let target: String
            let display: String
            if let pipe = body.firstIndex(of: "|") {
                target = String(body[..<pipe])
                display = String(body[body.index(after: pipe)...])
            } else {
                target = body
                display = body
            }
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            // Escape brackets in the link label so nested markdown stays stable.
            let label = display
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            let replacement = "[\(label)](lyra-wiki:\(encoded))"
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Decode a `lyra-wiki:` URL produced by `prepareInlineMarkdown` back to the note name.
    static func wikiLinkName(from url: URL) -> String? {
        guard url.scheme == "lyra-wiki" else { return nil }
        // lyra-wiki:Note%20Name — host is empty; path or resourceSpecifier holds the rest.
        let raw = url.absoluteString
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let encoded = String(raw[raw.index(after: colon)...])
        return encoded.removingPercentEncoding ?? encoded
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
            let body = String(trimmed.dropFirst(2))
            if body.hasPrefix("[ ] ") {
                return .listItem(
                    text: String(body.dropFirst(4)),
                    ordinal: nil,
                    depth: depth,
                    taskChecked: false
                )
            }
            if body.hasPrefix("[x] ") || body.hasPrefix("[X] ") {
                return .listItem(
                    text: String(body.dropFirst(4)),
                    ordinal: nil,
                    depth: depth,
                    taskChecked: true
                )
            }
            return .listItem(text: body, ordinal: nil, depth: depth, taskChecked: nil)
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#) else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 2 else { return nil }
        let ordinal = Int(ns.substring(with: match.range(at: 1)))
        let text = ns.substring(with: match.range(at: 2))
        return .listItem(text: text, ordinal: ordinal, depth: depth, taskChecked: nil)
    }
}
