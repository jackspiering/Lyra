import Foundation

/// Filename stem is the note’s identity (tab chip + title field).
enum NoteTitle {
    /// Tab chip and title-field value. Empty when no file is open. Reads only
    /// the URL, so observers do not redraw on every keystroke.
    static func displayTitle(fileURL: URL?) -> String {
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
    /// Invalid titles return an error instead of silently falling back.
    static func applyingTitle(_ newTitle: String, to markdown: String) -> (markdown: String, renamedStem: String?, error: String?) {
        switch FilenameValidation.validate(newTitle, isDirectory: false) {
        case .invalid(let detail):
            return (markdown, nil, detail)
        case .ok(let name):
            let stem = (name as NSString).deletingPathExtension
            return (markdown, stem, nil)
        }
    }
}
