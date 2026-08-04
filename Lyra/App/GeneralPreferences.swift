import Foundation

/// UserDefaults keys and accessors for General settings.
enum GeneralPreferences {
    static let promptForNewNoteNameKey = "lyra.promptForNewNoteName"
    static let defaultNoteStemKey = "lyra.defaultNoteStem"
    static let confirmDeleteKey = "lyra.confirmDelete"

    /// Show the name dialog when creating a note. Default `true`.
    static var promptForNewNoteName: Bool {
        if UserDefaults.standard.object(forKey: promptForNewNoteNameKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: promptForNewNoteNameKey)
    }

    /// Stem for auto-named notes (no extension). Default `"Untitled"`.
    /// Always sanitized: illegal characters / empty / trailing `.md` stripped.
    static var defaultNoteStem: String {
        let raw = UserDefaults.standard.string(forKey: defaultNoteStemKey) ?? "Untitled"
        return FilenameValidation.sanitizeNoteStem(raw)
    }

    /// Confirm before moving items to Trash. Default `true`.
    static var confirmDelete: Bool {
        if UserDefaults.standard.object(forKey: confirmDeleteKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: confirmDeleteKey)
    }
}
