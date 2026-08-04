import AppKit

enum MarkdownHighlighter {
    private static let baseFont = LyraFonts.ui(size: 14)
    private static let boldFont = LyraFonts.ui(size: 14, weight: .bold)

    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: NSColor.textColor,
    ]

    /// Precompiled once; applied in place so undo / IME composition stay intact.
    private static let rules: [(NSRegularExpression, [NSAttributedString.Key: Any])] = {
        let heading: [NSAttributedString.Key: Any] = [
            .foregroundColor: LyraTheme.heading,
            .font: boldFont,
        ]
        let code: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.code]
        let emphasis: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.emphasis]
        let link: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.link]
        let wiki: [NSAttributedString.Key: Any] = [
            .foregroundColor: LyraTheme.wiki,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let list: [NSAttributedString.Key: Any] = [.foregroundColor: LyraTheme.listMarker]
        let bold: [NSAttributedString.Key: Any] = [.font: boldFont]

        let patterns: [(String, [NSAttributedString.Key: Any])] = [
            (#"(?m)^(#{1,6})\s+.*$"#, heading),
            (#"`[^`\n]+`"#, code),
            (#"(?m)^```.*$"#, code),
            (#"\*\*[^*\n]+\*\*"#, bold),
            (#"(?<!\*)\*[^*\n]+\*(?!\*)"#, emphasis),
            (#"\[[^\]]+\]\([^)]+\)"#, link),
            (#"\[\[[^\]]+\]\]"#, wiki),
            (#"(?m)^\s*([-*+]|\d+\.)\s+"#, list),
        ]

        return patterns.compactMap { pattern, attrs in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, attrs)
        }
    }()

    /// Apply syntax attributes over `range` (or the whole storage) without replacing characters.
    static func applyHighlighting(to storage: NSTextStorage, range: NSRange? = nil) {
        let length = storage.length
        guard length > 0 else { return }

        let full = NSRange(location: 0, length: length)
        let target: NSRange
        if let range {
            let clamped = NSIntersectionRange(range, full)
            guard clamped.length > 0 || clamped.location < length else { return }
            target = (storage.string as NSString).paragraphRange(for: clamped)
        } else {
            target = full
        }

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: target)
        let source = storage.string
        for (regex, attrs) in rules {
            regex.enumerateMatches(in: source, range: target) { match, _, _ in
                guard let match else { return }
                storage.addAttributes(attrs, range: match.range)
            }
        }
        storage.endEditing()
    }

    /// Full restyle as a new attributed string (document load / tests).
    static func attributedString(from source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source, attributes: baseAttributes)
        let storage = NSTextStorage(attributedString: result)
        applyHighlighting(to: storage)
        return NSAttributedString(attributedString: storage)
    }
}
