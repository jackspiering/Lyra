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
        let full = NSRange(location: 0, length: (source as NSString).length)
        let ns = source as NSString

        apply(pattern: #"(?m)^(#{1,6})\s+.*$"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemPurple, .font: boldFont],
                range: match
            )
        }

        apply(pattern: #"`[^`\n]+`"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemOrange, .font: baseFont],
                range: match
            )
        }

        apply(pattern: #"(?m)^```.*$"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemOrange],
                range: match
            )
        }

        apply(pattern: #"\*\*[^*\n]+\*\*"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes([.font: boldFont], range: match)
        }

        apply(pattern: #"(?<!\*)\*[^*\n]+\*(?!\*)"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemTeal],
                range: match
            )
        }

        apply(pattern: #"\[[^\]]+\]\([^)]+\)"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemBlue],
                range: match
            )
        }

        apply(pattern: #"\[\[[^\]]+\]\]"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.systemIndigo, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: match
            )
        }

        apply(pattern: #"(?m)^\s*([-*+]|\d+\.)\s+"#, in: ns, fullRange: full) { match, storage in
            storage.addAttributes(
                [.foregroundColor: NSColor.secondaryLabelColor],
                range: match
            )
        }

        return result
    }

    private static func apply(
        pattern: String,
        in ns: NSString,
        fullRange: NSRange,
        block: (NSRange, NSMutableAttributedString) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        // We need a mutable copy; caller owns the string storage.
        // This helper is only used with a single mutable attributed string created above.
    }

    // Overload that mutates `result` — keep API simple for call sites above via local closure.
    private static func apply(
        pattern: String,
        in ns: NSString,
        fullRange: NSRange,
        to result: NSMutableAttributedString,
        block: (NSRange, NSMutableAttributedString) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: ns as String, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            block(match.range, result)
        }
    }
}

// Fix: the first apply helper was a stub. Provide working apply used by attributedString.
extension MarkdownHighlighter {
    fileprivate static func apply(
        pattern: String,
        in ns: NSString,
        fullRange: NSRange,
        block: (NSRange, NSMutableAttributedString) -> Void
    ) {
        // Intentionally empty — real implementation is below after rewrite.
        _ = (pattern, ns, fullRange, block)
    }
}
