import Foundation

/// Lightweight Markdown block split for the native preview (no WebKit).
enum MarkdownPreviewBlocks {
    private static let wikiDestinationAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return allowed
    }()

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

            if let fence = parseFence(raw) {
                flushParagraph()
                i += 1
                var code: [String] = []
                while i < lines.count, !isClosingFence(lines[i].text, for: fence) {
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
        // Find matching delimiter runs instead of toggling on every backtick;
        // otherwise a double-backtick span rewrites its wiki link as plain text.
        var result = ""
        var outsideStart = source.startIndex
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard source[cursor] == "`" else {
                cursor = source.index(after: cursor)
                continue
            }

            let openingStart = cursor
            let openingEnd = endOfBacktickRun(in: source, startingAt: cursor)
            let length = source.distance(from: openingStart, to: openingEnd)
            guard let closing = closingBacktickRun(
                in: source,
                after: openingEnd,
                length: length
            ) else {
                cursor = openingEnd
                continue
            }

            result += rewriteWikis(in: String(source[outsideStart..<openingStart]))
            result += String(source[openingStart..<closing.endIndex])
            cursor = closing.endIndex
            outsideStart = cursor
        }
        result += rewriteWikis(in: String(source[outsideStart...]))
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
                target = String(body[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
                display = String(body[body.index(after: pipe)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                target = body.trimmingCharacters(in: .whitespacesAndNewlines)
                display = target
            }
            let encoded = target.addingPercentEncoding(withAllowedCharacters: wikiDestinationAllowed) ?? target
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

    // MARK: - Line split

    private struct Line {
        let text: String
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
            lines.append(Line(text: ns.substring(with: NSRange(location: start, length: len))))
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

    private struct Fence {
        let marker: Character
        let length: Int
    }

    private static func parseFence(_ raw: String) -> Fence? {
        var index = raw.startIndex
        var indentation = 0
        while index < raw.endIndex, (raw[index] == " " || raw[index] == "\t"), indentation < 4 {
            indentation += raw[index] == "\t" ? 4 : 1
            index = raw.index(after: index)
        }
        guard indentation <= 3, index < raw.endIndex else { return nil }
        let marker = raw[index]
        guard marker == "`" || marker == "~" else { return nil }

        let runStart = index
        while index < raw.endIndex, raw[index] == marker {
            index = raw.index(after: index)
        }
        let length = raw.distance(from: runStart, to: index)
        guard length >= 3 else { return nil }
        if marker == "`", raw[index...].contains("`") { return nil }
        return Fence(marker: marker, length: length)
    }

    private static func isClosingFence(_ raw: String, for fence: Fence) -> Bool {
        var index = raw.startIndex
        var indentation = 0
        while index < raw.endIndex, (raw[index] == " " || raw[index] == "\t"), indentation < 4 {
            indentation += raw[index] == "\t" ? 4 : 1
            index = raw.index(after: index)
        }
        guard indentation <= 3, index < raw.endIndex, raw[index] == fence.marker else {
            return false
        }

        let runStart = index
        while index < raw.endIndex, raw[index] == fence.marker {
            index = raw.index(after: index)
        }
        let length = raw.distance(from: runStart, to: index)
        guard length >= fence.length else { return false }
        return raw[index...].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func endOfBacktickRun(in source: String, startingAt start: String.Index) -> String.Index {
        var index = start
        while index < source.endIndex, source[index] == "`" {
            index = source.index(after: index)
        }
        return index
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
            let runEnd = endOfBacktickRun(in: source, startingAt: index)
            if source.distance(from: runStart, to: runEnd) == length {
                return runStart..<runEnd
            }
            index = runEnd
        }
        return nil
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
