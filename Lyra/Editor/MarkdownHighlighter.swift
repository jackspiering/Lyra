import AppKit

enum MarkdownHighlighter {
    private static let baseFont = LyraFonts.ui(size: 14)
    private static let boldFont = LyraFonts.ui(size: 14, weight: .bold)

    private static let rules: [(String, [NSAttributedString.Key: Any])] = {
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
        return [
            (#"(?m)^(#{1,6})\s+.*$"#, heading),
            (#"`[^`\n]+`"#, code),
            (#"(?m)^```.*$"#, code),
            (#"\*\*[^*\n]+\*\*"#, bold),
            (#"(?<!\*)\*[^*\n]+\*(?!\*)"#, emphasis),
            (#"\[[^\]]+\]\([^)]+\)"#, link),
            (#"\[\[[^\]]+\]\]"#, wiki),
            (#"(?m)^\s*([-*+]|\d+\.)\s+"#, list),
        ]
    }()

    static func attributedString(from source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: source,
            attributes: [.font: baseFont, .foregroundColor: NSColor.textColor]
        )
        let full = NSRange(location: 0, length: (source as NSString).length)
        for (pattern, attrs) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            regex.enumerateMatches(in: source, range: full) { match, _, _ in
                guard let match else { return }
                result.addAttributes(attrs, range: match.range)
            }
        }
        return result
    }
}
