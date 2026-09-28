import Foundation

/// Reads only a leading YAML `aliases:` key. All other frontmatter is ordinary text.
enum FrontmatterAliases {
    /// Names listed in a leading `---` … `---` block under `aliases:`.
    static func parse(from markdown: String) -> [String] {
        guard let block = leadingFrontmatterLines(markdown) else { return [] }
        return aliases(from: block)
    }

    private static func leadingFrontmatterLines(_ markdown: String) -> [String]? {
        let lines = splitLines(markdown)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        var body: [String] = []
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return body
            }
            body.append(lines[i])
            i += 1
        }
        return nil
    }

    private static func aliases(from lines: [String]) -> [String] {
        var result: [String] = []
        var inList = false
        for line in lines {
            let indentation = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("aliases:") {
                // Only a top-level key participates. Nested `aliases:` keys and
                // block scalars are ordinary YAML and must not become wiki names.
                guard indentation == 0 else {
                    inList = false
                    continue
                }
                let rest = stripComment(
                    String(trimmed.dropFirst("aliases:".count))
                        .trimmingCharacters(in: .whitespaces)
                )
                if rest.isEmpty {
                    inList = true
                    continue
                }
                inList = false
                if rest.hasPrefix("["), rest.hasSuffix("]") {
                    let inner = rest.dropFirst().dropLast()
                    result.append(contentsOf: splitFlowList(String(inner)).compactMap {
                        let name = unquote($0.trimmingCharacters(in: .whitespaces))
                        return name.isEmpty ? nil : name
                    })
                } else {
                    let name = unquote(rest)
                    if !name.isEmpty { result.append(name) }
                }
                continue
            }
            if inList {
                if indentation > 0, trimmed.hasPrefix("-") {
                    let value = stripComment(
                        trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                    )
                    let name = unquote(value)
                    if !name.isEmpty { result.append(name) }
                } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                    inList = false
                }
            }
        }
        return result
    }

    /// Removes a `#` comment that starts outside single/double quotes.
    private static func stripComment(_ raw: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\", quote == "\"" {
                result.append(character)
                escaped = true
            } else if character == "\"", quote == nil {
                quote = character
                result.append(character)
            } else if character == "'", quote == nil {
                quote = character
                result.append(character)
            } else if let openQuote = quote, character == openQuote {
                quote = nil
                result.append(character)
            } else if character == "#", quote == nil {
                break
            } else {
                result.append(character)
            }
            index = raw.index(after: index)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Splits a flow list on commas outside single/double quotes.
    private static func splitFlowList(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in raw {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote == "\"" {
                current.append(character)
                escaped = true
            } else if (character == "\"" || character == "'"), quote == nil {
                quote = character
                current.append(character)
            } else if let openQuote = quote, character == openQuote {
                quote = nil
                current.append(character)
            } else if character == ",", quote == nil {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private static func unquote(_ raw: String) -> String {
        if raw.count >= 2 {
            if raw.hasPrefix("\""), raw.hasSuffix("\"") {
                let inner = String(raw.dropFirst().dropLast())
                return inner
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            if raw.hasPrefix("'"), raw.hasSuffix("'") {
                return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
        }
        return raw
    }

    private static func splitLines(_ source: String) -> [String] {
        let ns = source as NSString
        var lines: [String] = []
        var i = 0
        while i < ns.length {
            let start = i
            while i < ns.length {
                let ch = ns.character(at: i)
                if ch == 0x0A || ch == 0x0D { break }
                i += 1
            }
            lines.append(ns.substring(with: NSRange(location: start, length: i - start)))
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
}
