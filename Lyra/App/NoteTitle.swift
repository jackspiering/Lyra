import Foundation

/// Pure rules for note display title (tab chip + title field) and applying edits.
///
/// Display: first non-empty block is a level-1 heading (`# Title`) → use that text;
/// otherwise the filename stem (`Welcome` for `Welcome.md`).
///
/// Apply: if an H1 exists as that first block, rewrite its text and leave the path alone;
/// otherwise request a file rename to a sanitized stem.
enum NoteTitle {
    /// Tab chip and title-field value for open notes.
    static func displayTitle(markdown: String, fileURL: URL?) -> String {
        if let h1 = firstLevel1HeadingText(in: markdown) {
            return h1
        }
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return ""
    }

    /// Commits a title-field edit into markdown and/or a rename stem.
    /// - Returns `renamedStem` only when there is no leading H1 (caller renames `stem.md`).
    /// - When an H1 exists, updates that heading line and returns `renamedStem: nil`.
    static func applyingTitle(_ newTitle: String, to markdown: String) -> (markdown: String, renamedStem: String?) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = markdown.components(separatedBy: "\n")
        if let lineIndex = firstLevel1HeadingLineIndex(in: lines) {
            let existing = lines[lineIndex]
            let prefix = h1Prefix(of: existing) ?? "# "
            let replacement = prefix + trimmed
            if existing == replacement {
                return (markdown, nil)
            }
            lines[lineIndex] = replacement
            return (lines.joined(separator: "\n"), nil)
        }
        let stem = FilenameValidation.sanitizeNoteStem(trimmed.isEmpty ? "Untitled" : trimmed)
        return (markdown, stem)
    }

    // MARK: - H1 scan

    /// Text of the first non-empty ATX level-1 heading, if that is the first non-empty line.
    static func firstLevel1HeadingText(in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: "\n")
        guard let idx = firstLevel1HeadingLineIndex(in: lines) else { return nil }
        return h1Body(of: lines[idx])
    }

    /// Index of the first non-empty line when it is `# …` (exactly one `#` + whitespace).
    private static func firstLevel1HeadingLineIndex(in lines: [String]) -> Int? {
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isLevel1Heading(trimmed) {
                return i
            }
            return nil
        }
        return nil
    }

    private static func isLevel1Heading(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("#") else { return false }
        // Exactly one `#`, then whitespace (CommonMark ATX).
        guard !trimmed.hasPrefix("##") else { return false }
        guard trimmed.count > 1 else { return false }
        let after = trimmed.index(after: trimmed.startIndex)
        return trimmed[after].isWhitespace
    }

    private static func h1Body(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isLevel1Heading(trimmed) else { return nil }
        let afterHash = trimmed.index(after: trimmed.startIndex)
        return trimmed[afterHash...].trimmingCharacters(in: .whitespaces)
    }

    /// Preserves leading indentation and the `#` + following spaces from the existing line.
    private static func h1Prefix(of line: String) -> String? {
        var i = line.startIndex
        while i < line.endIndex, line[i] == " " || line[i] == "\t" {
            i = line.index(after: i)
        }
        guard i < line.endIndex, line[i] == "#" else { return nil }
        let afterHash = line.index(after: i)
        guard afterHash < line.endIndex, line[afterHash].isWhitespace else { return nil }
        var j = afterHash
        while j < line.endIndex, line[j].isWhitespace {
            j = line.index(after: j)
        }
        return String(line[..<j])
    }
}
