import Foundation

/// Filename stem is the note’s identity (tab chip + title field).
enum NoteTitle {
    /// Tab chip and title-field value. Ignores markdown. Empty when no file is open.
    static func displayTitle(markdown _: String, fileURL: URL?) -> String {
        fileURL?.deletingPathExtension().lastPathComponent ?? ""
    }

    /// Vault name then each folder above the note (`["Field Notes", "Essays"]`).
    /// Empty when there is no note or it sits outside the vault.
    static func breadcrumb(fileURL: URL?, vaultRoot: URL?) -> [String] {
        guard let fileURL, let vaultRoot else { return [] }
        let root = vaultRoot.standardizedFileURL.pathComponents
        let folder = fileURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard folder.count >= root.count, Array(folder.prefix(root.count)) == root else { return [] }
        return [vaultRoot.lastPathComponent] + folder.dropFirst(root.count)
    }

    /// Title-field commit always requests a rename. Markdown is unchanged.
    static func applyingTitle(_ newTitle: String, to markdown: String) -> (markdown: String, renamedStem: String?) {
        let stem = FilenameValidation.sanitizeNoteStem(newTitle)
        return (markdown, stem)
    }
}
