import AppKit

enum MarkdownHighlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    private static let rules: [(String, [NSAttributedString.Key: Any])] = {
        let purple: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemPurple, .font: boldFont]
        let orange: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemOrange]
        let teal: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemTeal]
        let blue: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemBlue]
        let wiki: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemIndigo,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let list: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.secondaryLabelColor]
        let bold: [NSAttributedString.Key: Any] = [.font: boldFont]
        return [
            (#"(?m)^(#{1,6})\s+.*$"#, purple),
            (#"`[^`\n]+`"#, orange),
            (#"(?m)^```.*$"#, orange),
            (#"\*\*[^*\n]+\*\*"#, bold),
            (#"(?<!\*)\*[^*\n]+\*(?!\*)"#, teal),
            (#"\[[^\]]+\]\([^)]+\)"#, blue),
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
