import Foundation

/// Filename stem is the note’s identity (tab chip + title field).
enum NoteTitle {
    /// Tab chip and title-field value. Ignores markdown. Empty when no file is open.
    static func displayTitle(markdown _: String, fileURL: URL?) -> String {
        fileURL?.deletingPathExtension().lastPathComponent ?? ""
    }

    /// Title-field commit always requests a rename. Markdown is unchanged.
    static func applyingTitle(_ newTitle: String, to markdown: String) -> (markdown: String, renamedStem: String?) {
        let stem = FilenameValidation.sanitizeNoteStem(newTitle)
        return (markdown, stem)
    }
}
