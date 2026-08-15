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
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("aliases:") {
                let rest = String(trimmed.dropFirst("aliases:".count))
                    .trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    inList = true
                    continue
                }
                inList = false
                if rest.hasPrefix("["), rest.hasSuffix("]") {
                    let inner = rest.dropFirst().dropLast()
                    result.append(contentsOf: inner.split(separator: ",").compactMap {
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
                if trimmed.hasPrefix("-") {
                    let value = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                    let name = unquote(value)
                    if !name.isEmpty { result.append(name) }
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    inList = false
                }
            }
        }
        return result
    }

    private static func unquote(_ raw: String) -> String {
        if raw.count >= 2 {
            if raw.hasPrefix("\""), raw.hasSuffix("\"") {
                return String(raw.dropFirst().dropLast())
            }
            if raw.hasPrefix("'"), raw.hasSuffix("'") {
                return String(raw.dropFirst().dropLast())
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
