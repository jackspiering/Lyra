import AppKit

enum MarkdownHighlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    static func attributedString(from source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
            ]
        )
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)

        highlight(pattern: #"(?m)^(#{1,6})\s+.*$"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemPurple, .font: boldFont],
                range: range
            )
        }

        highlight(pattern: #"`[^`\n]+`"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemOrange],
                range: range
            )
        }

        highlight(pattern: #"(?m)^```.*$"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemOrange],
                range: range
            )
        }

        highlight(pattern: #"\*\*[^*\n]+\*\*"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes([.font: boldFont], range: range)
        }

        highlight(pattern: #"(?<!\*)\*[^*\n]+\*(?!\*)"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemTeal],
                range: range
            )
        }

        highlight(pattern: #"\[[^\]]+\]\([^)]+\)"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemBlue],
                range: range
            )
        }

        highlight(pattern: #"\[\[[^\]]+\]\]"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.systemIndigo,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )
        }

        highlight(pattern: #"(?m)^\s*([-*+]|\d+\.)\s+"#, in: ns, fullRange: full, onto: result) { range, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.secondaryLabelColor],
                range: range
            )
        }

        return result
    }

    private static func highlight(
        pattern: String,
        in ns: NSString,
        fullRange: NSRange,
        onto storage: NSMutableAttributedString,
        apply: (NSRange, NSMutableAttributedString) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: ns as String, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            apply(match.range, storage)
        }
    }
}
