import Foundation

/// Lightweight Markdown block split for the native preview (no WebKit).
enum MarkdownPreviewBlocks {
    private static let wikiDestinationAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return allowed
    }()
    private static let orderedItemPattern = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s+(.*)$"#)

    enum Block: Hashable {
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
        let lines = MarkdownScan.lines(source)
        var i = 0
        var paragraph: [String] = []

        // Leading YAML frontmatter is ordinary text, shown as a code block
        // rather than two rules around a paragraph.
        if let frontmatterEnd = MarkdownScan.frontmatterEnd(in: lines) {
            blocks.append(.code(lines[1..<frontmatterEnd].joined(separator: "\n")))
            i = frontmatterEnd + 1
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            if let image = MarkdownImagePath.parseImageLine(text) {
                blocks.append(.image(alt: image.alt, path: image.path))
            } else {
                blocks.append(.paragraph(text))
            }
        }

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if let fence = MarkdownScan.Fence(opening: raw) {
                flushParagraph()
                i += 1
                var code: [String] = []
                while i < lines.count, !fence.isClosed(by: lines[i]) {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if !paragraph.isEmpty, let setextLevel = parseSetextUnderline(trimmed) {
                let headingText = paragraph
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                paragraph.removeAll()
                if !headingText.isEmpty {
                    blocks.append(.heading(level: setextLevel, text: headingText))
                }
                i += 1
                continue
            }

            if isThematicBreak(trimmed) {
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

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var body = trimmed
                while body.hasPrefix(">") {
                    body.removeFirst()
                    if body.hasPrefix(" ") {
                        body.removeFirst()
                    }
                }
                blocks.append(.quote(body.trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }

            if let item = parseListItem(raw: raw, trimmed: trimmed) {
                flushParagraph()
                blocks.append(item)
                i += 1
                continue
            }

            if !trimmed.isEmpty, paragraph.isEmpty,
               case .listItem(let text, let ordinal, let depth, let taskChecked)? = blocks.last,
               isIndentedContinuation(raw) {
                blocks[blocks.count - 1] = .listItem(
                    text: text + "\n" + trimmed,
                    ordinal: ordinal,
                    depth: depth,
                    taskChecked: taskChecked
                )
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraph.append(raw)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    /// Inline Markdown (emphasis, code, links, wiki links) parsed the way
    /// Reading and PDF export show it. `nil` when parsing fails.
    static func inlineAttributedString(_ source: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return try? AttributedString(markdown: prepareInlineMarkdown(source), options: options)
    }

    /// Turn `[[wiki]]` links outside code into Markdown links with a
    /// `lyra-wiki:` destination, so Reading can open them. `[[path|alias]]`
    /// shows the alias. Embeds and heading links stay as written.
    static func prepareInlineMarkdown(_ source: String) -> String {
        let result = NSMutableString(string: source)
        for link in WikiLinkSyntax.extractLinks(in: source).reversed() {
            let inner = link.inner
            let target = (inner.firstIndex(of: "|").map { String(inner[..<$0]) } ?? inner)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // `[[Note|]]` has an empty alias; show the target instead of an invisible link.
            let display = WikiLinkSyntax.parseInner(inner).display ?? target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: wikiDestinationAllowed) ?? target
            // Escape brackets in the link label so nested markdown stays stable.
            let label = display
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            result.replaceCharacters(in: link.range, with: "[\(label)](lyra-wiki:\(encoded))")
        }
        return result as String
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

    /// What a click on a Reading link does.
    enum LinkTarget: Equatable {
        case wiki(String)
        case note(URL)
        case external(URL)
        case unsupported
    }

    /// Web and mail links open in the system handler. A `file:` link opens
    /// only when it stays inside the vault and is a plain, non-executable
    /// file (an attachment, not an app or script). Relative links to Markdown
    /// notes inside the vault open as notes. Every other scheme is ignored so
    /// a note from a shared vault cannot launch apps.
    static func linkTarget(for url: URL, noteDirectory: URL?, vaultRoot: URL?) -> LinkTarget {
        if let name = wikiLinkName(from: url) { return .wiki(name) }
        if let scheme = url.scheme?.lowercased() {
            if ["http", "https", "mailto"].contains(scheme) { return .external(url) }
            guard scheme == "file", let vaultRoot, isOpenableAttachment(url, vaultRoot: vaultRoot) else {
                return .unsupported
            }
            return .external(url)
        }
        guard let noteDirectory, let vaultRoot else { return .unsupported }
        let path = url.relativePath
        guard (path as NSString).pathExtension.lowercased() == "md",
              let note = MarkdownImagePath.resolve(path: path, noteDirectory: noteDirectory, vaultRoot: vaultRoot)
        else {
            return .unsupported
        }
        return .note(note)
    }

    private static func isOpenableAttachment(_ url: URL, vaultRoot: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileSystemVault.isSafePath(url, within: vaultRoot)
            && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && !FileManager.default.isExecutableFile(atPath: url.path)
    }

    // MARK: - Line kinds

    private static func parseSetextUnderline(_ trimmed: String) -> Int? {
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3,
              let marker = compact.first,
              marker == "*" || marker == "-" || marker == "_" else {
            return false
        }
        return compact.allSatisfy { $0 == marker }
    }

    private static func isIndentedContinuation(_ raw: String) -> Bool {
        raw.hasPrefix("  ") || raw.hasPrefix("\t")
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
        guard let regex = orderedItemPattern else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 2 else { return nil }
        let ordinal = Int(ns.substring(with: match.range(at: 1)))
        let text = ns.substring(with: match.range(at: 2))
        return .listItem(text: text, ordinal: ordinal, depth: depth, taskChecked: nil)
    }
}
