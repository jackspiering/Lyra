import AppKit

/// Source-mode styling. Text stays plain Markdown: syntax markers remain in the
/// buffer but are drawn quietly, and structure (headings, code, quotes) gets
/// size and color so the page reads like prose. Not WYSIWYG — nothing is hidden.
enum MarkdownHighlighter {
    private static let baseFont = LyraFonts.ui(size: LyraFonts.proseSize)
    private static let codeFont = LyraFonts.code(size: LyraFonts.proseSize - 1.5)

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = LyraFonts.proseLineSpacing
        return style
    }()

    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: LyraTheme.ink,
        .paragraphStyle: paragraphStyle,
    ]

    private static let fencedCodeAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: LyraTheme.code,
        .font: codeFont,
    ]

    private struct Rule {
        let regex: NSRegularExpression
        /// Applied to the whole match.
        var attributes: [NSAttributedString.Key: Any] = [:]
        /// Applied to individual capture groups (after `attributes`).
        var groups: [Int: [NSAttributedString.Key: Any]] = [:]
        /// Swap every font in the match for the bold face at the same size.
        var embolden = false
        /// Fence delimiters style even inside fenced code; other Markdown rules do not.
        var skipInFencedCode = true
    }

    private static let headingRegex = try? NSRegularExpression(pattern: #"(?m)^(#{1,6})[ \t]+.*$"#)

    /// Heading attributes indexed by level − 1.
    private static let headingAttributes: [[NSAttributedString.Key: Any]] = (1...6).map { level -> [NSAttributedString.Key: Any] in
        let style = NSMutableParagraphStyle()
        style.lineSpacing = LyraFonts.proseLineSpacing
        style.paragraphSpacingBefore = level <= 2 ? 10 : 6
        return [
            .font: LyraFonts.ui(
                size: LyraFonts.headingSize(level: level),
                weight: level <= 2 ? .bold : .semibold
            ),
            .foregroundColor: LyraTheme.heading,
            .paragraphStyle: style,
        ]
    }

    /// Precompiled once; applied in place so undo / IME composition stay intact.
    /// Later rules win where they overlap.
    private static let rules: [Rule] = {
        let marker: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.markup]
        let accent: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.accent]
        let inlineCode: [NSAttributedString.Key: Any] = [
            .foregroundColor: LyraTheme.code,
            .font: codeFont,
            .backgroundColor: LyraTheme.codeBackground,
        ]
        let emphasis: [NSAttributedString.Key: Any] = [
            .foregroundColor: LyraTheme.emphasis,
            .obliqueness: 0.14,
        ]
        let link: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.link]
        let wiki: [NSAttributedString.Key: Any] = [
            .foregroundColor: LyraTheme.wiki,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let quote: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.quote]

        let list: [Rule?] = [
            // Fence lines (```lang / ~~~).
            rule(#"(?m)^[ \t]{0,3}(```|~~~).*$"#, attributes: fencedCodeAttributes, groups: [1: marker], skipInFencedCode: false),
            // **bold**
            rule(#"(\*\*)([^*\n]+)(\*\*)"#, groups: [1: marker, 3: marker], embolden: true),
            // *emphasis* and _emphasis_
            rule(#"(?<!\*)(\*)([^*\n]+)(\*)(?!\*)"#, groups: [1: marker, 2: emphasis, 3: marker]),
            rule(#"(?<![\w_])(_)([^_\n]+)(_)(?![\w_])"#, groups: [1: marker, 2: emphasis, 3: marker]),
            // [text](url)
            rule(#"(\[)([^\]\n]+)(\]\([^)\n]+\))"#, groups: [1: marker, 2: link, 3: marker]),
            // [[wiki]]
            rule(#"(\[\[)([^\]\n]+)(\]\])"#, groups: [1: marker, 2: wiki, 3: marker]),
            // List bullets, ordinals, and task boxes.
            rule(#"(?m)^[ \t]*([-*+]|\d+[.)])[ \t]+(\[[ xX]\])?"#, groups: [1: accent, 2: accent]),
            // > quote
            rule(#"(?m)^[ \t]*(>+)[ \t]?(.*)$"#, groups: [1: accent, 2: quote]),
            // --- / *** / ___
            rule(#"(?m)^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#, attributes: marker),
            // `inline code` last so it wins over emphasis inside backticks.
            rule(#"(`)([^`\n]+)(`)"#, groups: [1: marker, 2: inlineCode, 3: marker]),
        ]
        return list.compactMap { $0 }
    }()

    private static func rule(
        _ pattern: String,
        attributes: [NSAttributedString.Key: Any] = [:],
        groups: [Int: [NSAttributedString.Key: Any]] = [:],
        embolden: Bool = false,
        skipInFencedCode: Bool = true
    ) -> Rule? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Rule(regex: regex, attributes: attributes, groups: groups, embolden: embolden, skipInFencedCode: skipInFencedCode)
    }

    /// Apply syntax attributes over `range` (or the whole storage) without replacing characters.
    static func applyHighlighting(to storage: NSTextStorage, range: NSRange? = nil) {
        let length = storage.length
        guard length > 0 else { return }

        let full = NSRange(location: 0, length: length)
        var target: NSRange
        if let range {
            // NSIntersectionRange collapses a zero-length caret at `length` to {0,0},
            // which restyles the first paragraph instead of the one being typed.
            let loc = min(max(0, range.location), length)
            let maxLen = length - loc
            let len = min(max(0, range.length), maxLen)
            let clamped = NSRange(location: loc, length: len)
            target = (storage.string as NSString).paragraphRange(for: clamped)
        } else {
            target = full
        }

        let source = storage.string
        let fencedRanges = WikiLinkSyntax.fencedCodeRanges(in: source)
        // Toggling a fence can restyle the rest of the document. Fall back to a
        // full pass only for edits containing a fence marker.
        if range != nil {
            let paragraphText = (source as NSString).substring(with: target)
            if paragraphText.contains("```") || paragraphText.contains("~~~") {
                target = full
            }
        }
        let fencedTargetRanges = fencedRanges.compactMap { fence -> NSRange? in
            let intersection = NSIntersectionRange(fence, target)
            return intersection.length > 0 ? intersection : nil
        }
        func intersectsFencedCode(_ candidate: NSRange) -> Bool {
            fencedTargetRanges.contains { NSIntersectionRange($0, candidate).length > 0 }
        }

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: target)
        for fenced in fencedTargetRanges {
            storage.addAttributes(fencedCodeAttributes, range: fenced)
        }

        headingRegex?.enumerateMatches(in: source, range: target) { match, _, _ in
            guard let match else { return }
            if intersectsFencedCode(match.range) { return }
            let hashes = match.range(at: 1)
            let level = min(max(hashes.length, 1), 6)
            storage.addAttributes(headingAttributes[level - 1], range: match.range)
            storage.addAttribute(.foregroundColor, value: LyraTheme.markup, range: hashes)
        }

        for rule in rules {
            rule.regex.enumerateMatches(in: source, range: target) { match, _, _ in
                guard let match else { return }
                if rule.skipInFencedCode, intersectsFencedCode(match.range) { return }
                if !rule.attributes.isEmpty {
                    storage.addAttributes(rule.attributes, range: match.range)
                }
                if rule.embolden {
                    embolden(storage, in: match.range)
                }
                for (group, attrs) in rule.groups where group < match.numberOfRanges {
                    let groupRange = match.range(at: group)
                    guard groupRange.location != NSNotFound, groupRange.length > 0 else { continue }
                    storage.addAttributes(attrs, range: groupRange)
                }
            }
        }
        storage.endEditing()
    }

    /// Bold at the current size, so `**bold**` inside a heading stays heading-sized.
    private static func embolden(_ storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let size = (value as? NSFont)?.pointSize ?? LyraFonts.proseSize
            storage.addAttribute(.font, value: LyraFonts.ui(size: size, weight: .bold), range: subrange)
        }
    }

    /// Full restyle as a new attributed string (document load / tests).
    static func attributedString(from source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source, attributes: baseAttributes)
        let storage = NSTextStorage(attributedString: result)
        applyHighlighting(to: storage)
        return NSAttributedString(attributedString: storage)
    }
}
