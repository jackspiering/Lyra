import Foundation

/// Line-level Markdown scanning shared by the wiki index, frontmatter aliases,
/// Source highlighting, and Reading: lines, a leading `---` block, and code fences.
enum MarkdownScan {
    /// Lines split on `\n`, `\r`, or `\r\n`, without their line breaks.
    static func lines(_ source: String) -> [String] {
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
            skipLineBreak(in: ns, at: &i)
        }
        return lines
    }

    /// Advances past one `\n`, `\r`, or `\r\n` at `i`, if there is one.
    static func skipLineBreak(in ns: NSString, at i: inout Int) {
        guard i < ns.length else { return }
        let ch = ns.character(at: i)
        if ch == 0x0D {
            i += 1
            if i < ns.length && ns.character(at: i) == 0x0A { i += 1 }
        } else if ch == 0x0A {
            i += 1
        }
    }

    /// Index of the line that closes a leading `---` block, or `nil` when the
    /// note does not start with a closed one.
    static func frontmatterEnd(in lines: [String]) -> Int? {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        return lines.indices.dropFirst().first {
            lines[$0].trimmingCharacters(in: .whitespaces) == "---"
        }
    }

    /// The opening run of a fenced code block: three or more backticks or
    /// tildes after at most three columns of indentation.
    struct Fence: Equatable {
        let marker: Character
        let length: Int

        /// The fence `line` opens, or `nil`. A backtick fence's info string
        /// may not contain a backtick.
        init?(opening line: String) {
            guard let run = Self.markerRun(in: line), run.length >= 3 else { return nil }
            if run.marker == "`", run.rest.contains("`") { return nil }
            marker = run.marker
            length = run.length
        }

        /// Whether `line` closes this fence: the same marker, at least as
        /// long, and nothing after it but spaces or tabs.
        func isClosed(by line: String) -> Bool {
            guard let run = Self.markerRun(in: line), run.marker == marker, run.length >= length else {
                return false
            }
            return run.rest.allSatisfy { $0 == " " || $0 == "\t" }
        }

        /// The run of backticks or tildes that starts `line`, after at most
        /// three columns of indentation (a tab counts as four).
        private static func markerRun(in line: String) -> (marker: Character, length: Int, rest: Substring)? {
            var index = line.startIndex
            var indentation = 0
            while index < line.endIndex, line[index] == " " || line[index] == "\t", indentation < 4 {
                indentation += line[index] == "\t" ? 4 : 1
                index = line.index(after: index)
            }
            guard indentation <= 3, index < line.endIndex else { return nil }
            let marker = line[index]
            guard marker == "`" || marker == "~" else { return nil }
            let runStart = index
            while index < line.endIndex, line[index] == marker {
                index = line.index(after: index)
            }
            return (marker, line.distance(from: runStart, to: index), line[index...])
        }
    }
}
