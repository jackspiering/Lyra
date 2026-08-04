import Foundation

/// UserDefaults keys and accessors for General settings.
enum GeneralPreferences {
    static let promptForNewNoteNameKey = "lyra.promptForNewNoteName"
    static let defaultNoteStemKey = "lyra.defaultNoteStem"
    /// Legacy single confirm key (pre-0.9.0). Migrated into note/folder keys.
    static let confirmDeleteKey = "lyra.confirmDelete"
    static let confirmDeleteNoteKey = "lyra.confirmDeleteNote"
    static let confirmDeleteFolderKey = "lyra.confirmDeleteFolder"

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

    /// Confirm before moving a note to Trash. Default `true`.
    static var confirmDeleteNote: Bool {
        migrateConfirmDeleteIfNeeded()
        if UserDefaults.standard.object(forKey: confirmDeleteNoteKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: confirmDeleteNoteKey)
    }

    /// Confirm before moving a folder to Trash. Default `true`.
    static var confirmDeleteFolder: Bool {
        migrateConfirmDeleteIfNeeded()
        if UserDefaults.standard.object(forKey: confirmDeleteFolderKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: confirmDeleteFolderKey)
    }

    /// One-shot: if the old combined key is set and either new key is missing, copy the bool.
    static func migrateConfirmDeleteIfNeeded() {
        let defaults = UserDefaults.standard
        let noteMissing = defaults.object(forKey: confirmDeleteNoteKey) == nil
        let folderMissing = defaults.object(forKey: confirmDeleteFolderKey) == nil
        guard noteMissing || folderMissing else { return }
        guard defaults.object(forKey: confirmDeleteKey) != nil else { return }
        let old = defaults.bool(forKey: confirmDeleteKey)
        if noteMissing {
            defaults.set(old, forKey: confirmDeleteNoteKey)
        }
        if folderMissing {
            defaults.set(old, forKey: confirmDeleteFolderKey)
        }
    }
}
