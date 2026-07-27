import Foundation

/// Short titles + plain-language alert bodies for vault I/O failures.
enum UserFacingError {
    enum Context: Equatable {
        case rememberVault
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

    static func presentable(for error: Error, context: Context) -> (title: String, message: String) {
        (context.title, message(for: error, context: context))
    }

    static func message(for error: Error, context: Context) -> String {
        "\(humanDetail(for: error))\n\n\(tip(for: context))"
    }

    static func message(context: Context, detail: String) -> String {
        "\(detail)\n\n\(tip(for: context))"
    }

    private static func humanDetail(for error: Error) -> String {
        let ns = error as NSError
        let code = ns.code
        let domain = ns.domain

        if domain == NSPOSIXErrorDomain {
            switch code {
            case Int(EACCES), Int(EPERM): return Self.permission
            case Int(ENOENT): return Self.missing
            case Int(ENOSPC): return Self.noSpace
            case Int(EROFS): return Self.readOnly
            case Int(EEXIST): return Self.exists
            default: break
            }
        }

        if domain == NSCocoaErrorDomain {
            switch code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return Self.permission
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return Self.missing
            case NSFileWriteOutOfSpaceError: return Self.noSpace
            case NSFileWriteVolumeReadOnlyError: return Self.readOnly
            case NSFileWriteFileExistsError: return Self.exists
            case NSFileWriteInvalidFileNameError: return "That name isn't valid for a file on this system."
            case NSFileLockingError: return "The file is locked or in use by another app."
            default: break
            }
        }

        let localized = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty, localized.count < 180, !localized.hasPrefix("The operation") {
            return localized
        }
        return ns.localizedFailureReason ?? "Something unexpected went wrong."
    }

    private static let permission = "Lyra doesn't have permission to access that location."
    private static let missing = "That file or folder could not be found. It may have been moved or deleted."
    private static let noSpace = "There isn't enough free space on the disk."
    private static let readOnly = "That disk or folder is read-only."
    private static let exists = "Something with that name already exists."

    private static func tip(for context: Context) -> String {
        switch context {
        case .rememberVault:
            return "You can still use the vault this session. Open Vault again next time if it doesn't reopen."
        case .readVault:
            return "Try Open Vault… again. Check System Settings → Privacy & Security → Files and Folders."
        case .openNote:
            return "Select the note again from the sidebar, or check that the file still exists."
        case .saveNote:
            return "Edits may not be on disk yet. Check permissions and free space, then press ⌘S."
        case .createNote, .createFolder:
            return "Check that the vault is writable and nothing already uses that name."
        case .rename:
            return "Try a different name, or check that nothing else is using the file."
        case .delete:
            return "The item may be locked or already removed."
        case .pasteImage:
            return "The image wasn't added. Check the vault is writable, then paste again (⌘V)."
        case .exportPDF:
            return "Try another save location and confirm free disk space."
        }
    }
}
