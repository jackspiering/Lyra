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

    /// The filename stem a title edit renames the note to, or why the title
    /// can't be a filename. The note's text is never touched.
    static func stem(forTitle title: String) -> FilenameValidation.Result {
        switch FilenameValidation.validate(title, isDirectory: false) {
        case .invalid(let detail):
            return .invalid(detail)
        case .ok(let name):
            return .ok((name as NSString).deletingPathExtension)
        }
    }
}
