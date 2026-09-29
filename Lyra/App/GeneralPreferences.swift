import Foundation

/// UserDefaults keys and accessors for General settings.
enum GeneralPreferences {
    static let promptForNewNoteNameKey = "lyra.promptForNewNoteName"
    static let defaultNoteStemKey = "lyra.defaultNoteStem"
    static let confirmDeleteNoteKey = "lyra.confirmDeleteNote"
    static let confirmDeleteFolderKey = "lyra.confirmDeleteFolder"

    /// Show the name dialog when creating a note. Default `true`.
    static var promptForNewNoteName: Bool {
        bool(forKey: promptForNewNoteNameKey, default: true)
    }

    /// Stem for auto-named notes (no extension). Default `"Untitled"`.
    /// Always sanitized: illegal characters / empty / trailing `.md` stripped.
    static var defaultNoteStem: String {
        let raw = UserDefaults.standard.string(forKey: defaultNoteStemKey) ?? "Untitled"
        return FilenameValidation.sanitizeNoteStem(raw)
    }

    /// Confirm before moving a note to Trash. Default `true`.
    static var confirmDeleteNote: Bool {
        bool(forKey: confirmDeleteNoteKey, default: true)
    }

    /// Confirm before moving a folder to Trash. Default `true`.
    static var confirmDeleteFolder: Bool {
        bool(forKey: confirmDeleteFolderKey, default: true)
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}
