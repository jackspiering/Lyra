import Foundation

/// Maps system errors into short titles and plain-language messages for alerts.
enum UserFacingError {
    enum Context: Equatable {
        case rememberVault
        case openVault
        case readVault
        case openNote
        case saveNote
        case createNote
        case createFolder
        case rename
        case delete
        case pasteImage
        case exportPDF

        var title: String {
            switch self {
            case .rememberVault: return "Couldn't remember this vault"
            case .openVault: return "Couldn't open vault"
            case .readVault: return "Couldn't read the vault"
            case .openNote: return "Couldn't open note"
            case .saveNote: return "Couldn't save note"
            case .createNote: return "Couldn't create note"
            case .createFolder: return "Couldn't create folder"
            case .rename: return "Couldn't rename"
            case .delete: return "Couldn't move to Trash"
            case .pasteImage: return "Couldn't paste image"
            case .exportPDF: return "Couldn't export PDF"
            }
        }
    }

    /// Title + multi-line body suitable for an alert.
    static func presentable(for error: Error, context: Context) -> (title: String, message: String) {
        (context.title, message(for: error, context: context))
    }

    static func message(for error: Error, context: Context) -> String {
        let detail = humanDetail(for: error)
        let tip = tip(for: context)
        if tip.isEmpty { return detail }
        return "\(detail)\n\n\(tip)"
    }

    /// Message when there is no underlying `Error` (e.g. createFile returned false).
    static func message(context: Context, detail: String) -> String {
        let tip = tip(for: context)
        if tip.isEmpty { return detail }
        return "\(detail)\n\n\(tip)"
    }

    // MARK: - Detail

    private static func humanDetail(for error: Error) -> String {
        let ns = error as NSError

        if ns.domain == NSPOSIXErrorDomain {
            switch ns.code {
            case Int(EACCES), Int(EPERM):
                return "Lyra doesn't have permission to access that location."
            case Int(ENOENT):
                return "That file or folder could not be found. It may have been moved or deleted."
            case Int(ENOSPC):
                return "There isn't enough free space on the disk."
            case Int(EROFS):
                return "That disk or folder is read-only."
            case Int(EEXIST):
                return "Something with that name already exists."
            default:
                break
            }
        }

        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return "Lyra doesn't have permission to access that location."
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "That file or folder could not be found. It may have been moved or deleted."
            case NSFileWriteOutOfSpaceError:
                return "There isn't enough free space on the disk."
            case NSFileWriteVolumeReadOnlyError:
                return "That disk or folder is read-only."
            case NSFileWriteFileExistsError:
                return "Something with that name already exists."
            case NSFileWriteInvalidFileNameError:
                return "That name isn't valid for a file on this system."
            case NSFileLockingError:
                return "The file is locked or in use by another app."
            default:
                break
            }
        }

        let localized = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty, localized.count < 180, !localized.hasPrefix("The operation") {
            return localized
        }
        if let reason = ns.localizedFailureReason, !reason.isEmpty {
            return reason
        }
        return "Something unexpected went wrong."
    }

    private static func tip(for context: Context) -> String {
        switch context {
        case .rememberVault:
            return "You can still use the vault this session. Choose Open Vault again next time if it doesn't reopen automatically."
        case .openVault, .readVault:
            return "Try choosing the folder again with Open Vault…, and confirm Lyra is allowed to access it in System Settings → Privacy & Security → Files and Folders."
        case .openNote:
            return "Select the note again from the sidebar, or check that the file still exists on disk."
        case .saveNote:
            return "Your latest edits may not be on disk yet. Check disk space and folder permissions, then press ⌘S to try again."
        case .createNote, .createFolder:
            return "Check that the vault folder is writable and that a file with the same name doesn't already exist."
        case .rename:
            return "Pick a different name, or check that nothing else is using the current file."
        case .delete:
            return "The item may be locked or already removed. Try again from Finder if needed."
        case .pasteImage:
            return "The image wasn't added to the note. Check that the vault is writable, then copy the image and paste again (⌘V)."
        case .exportPDF:
            return "Try a different save location, and confirm there is free disk space."
        }
    }
}
