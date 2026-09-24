import Foundation
import Observation

@MainActor
@Observable
final class EditorViewModel {
    var fileURL: URL?
    /// Current vault root, when the editor belongs to a vault window. Used to
    /// reject writes redirected through a replaced symlinked ancestor.
    var vaultRoot: URL?
    var text: String = ""
    var isDirty = false
    /// Last save/open failure for the UI to present.
    var lastError: (context: UserFacingError.Context, error: Error)?
    /// Disk identity changed under us while dirty — UI offers Keep Mine / Reload.
    var hasExternalConflict = false
    /// Open note path no longer exists (moved/deleted outside Lyra).
    var hasMissingFile = false
    /// Sticky: last write failed; cleared only on a successful save/open/reload.
    private(set) var lastSaveFailed = false
    /// User dismissed the conflict dialog; autosave stays off until Keep Mine / Reload / ⌘S.
    private(set) var conflictDeferred = false
    /// File creation date from disk attributes (status bar).
    private(set) var createdAt: Date?
    /// Last successful save time, or file mtime after open/reload when clean.
    private(set) var lastSavedAt: Date?

    /// True while there is an error the UI has not yet flushed.
    var hasError: Bool { lastError != nil }

    /// File identity observed at the last successful open/save/reload.
    ///
    /// Metadata alone is not enough here: an atomic replacement can retain the
    /// same path, size, and coarse-grained modification date. Keep the bytes
    /// too so conflict detection remains conservative on filesystems with a
    /// low timestamp resolution.
    struct DiskSnapshot: Equatable {
        let path: String
        let date: Date
        let size: Int
        let device: UInt64?
        let inode: UInt64?
        let content: Data

        func hasSameFileIdentity(as other: DiskSnapshot) -> Bool {
            date == other.date
                && size == other.size
                && device == other.device
                && inode == other.inode
                && content == other.content
        }
    }

    private struct FileMetadata: Equatable {
        let date: Date
        let size: Int
        let device: UInt64?
        let inode: UInt64?
    }

    private var diskSnapshot: DiskSnapshot?
    private var saveTask: Task<Void, Never>?

    /// Opens `url` after flushing dirty state. Returns `false` if a dirty save failed;
    /// in that case `text` / `fileURL` / `isDirty` are left unchanged so the user can retry.
    @discardableResult
    func open(url: URL) -> Bool {
        guard saveIfNeeded() else { return false }
        guard let (readText, snapshot) = Self.readTextAndSnapshot(of: url) else {
            // Do not discard the active note when the requested target cannot
            // be read. The user must still be able to retry or keep editing it.
            lastError = (.openNote, CocoaError(.fileReadUnknown))
            return false
        }
        text = readText
        fileURL = url
        isDirty = false
        lastError = nil
        lastSaveFailed = false
        hasExternalConflict = false
        hasMissingFile = false
        conflictDeferred = false
        diskSnapshot = snapshot
        refreshFileDates(for: url, markSavedNow: false)
        return true
    }

    /// Point the editor at a new path without saving (e.g. after rename).
    func relocate(to newURL: URL) {
        saveTask?.cancel()
        saveTask = nil
        fileURL = newURL
        hasMissingFile = false
        hasExternalConflict = false
        conflictDeferred = false
        lastError = nil
        lastSaveFailed = false
        rememberDiskSnapshot(for: newURL)
        refreshFileDates(for: newURL, markSavedNow: false)
    }

    /// Cancel on the conflict dialog: stop autosaving without treating Cancel as overwrite.
    func deferConflict() {
        guard hasExternalConflict || hasMissingFile else { return }
        hasExternalConflict = false
        conflictDeferred = true
        saveTask?.cancel()
        saveTask = nil
    }

    /// Closes the current note after flushing dirty state. Returns `false` if
    /// save failed or the file disappeared so the UI can offer recovery.
    @discardableResult
    func close() -> Bool {
        if isDirty, let url = fileURL, !FileManager.default.fileExists(atPath: url.path) {
            hasMissingFile = true
            lastSaveFailed = true
            return false
        }
        guard saveIfNeeded() else { return false }
        clearBuffer()
        return true
    }

    /// Explicitly discard the in-memory buffer after the user confirms a
    /// missing-file close. Normal close never takes this destructive path.
    func discardAndClose() {
        clearBuffer()
    }

    /// Call after `text` has already been updated (e.g. via Binding).
    func noteEdited() {
        guard fileURL != nil else { return }
        isDirty = true
        scheduleAutosave()
    }

    /// Writes if dirty. Returns `false` when a write was attempted and failed or was blocked
    /// by an external disk change (`hasExternalConflict` is set) or a missing file
    /// (`hasMissingFile` is set). Pass `force: true` to overwrite disk after Keep Mine,
    /// or to recreate a missing file at the current path.
    ///
    /// Explicit saves (⌘S) pass through even when `conflictDeferred` is set, so the conflict
    /// dialog can reappear. Autosave is gated separately in `scheduleAutosave`.
    @discardableResult
    func saveIfNeeded(force: Bool = false) -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let url = fileURL else { return true }

        if !FileManager.default.fileExists(atPath: url.path) {
            if force {
                return writeToDisk(url, force: true)
            }
            hasMissingFile = true
            lastSaveFailed = true
            return false
        }

        if !force, hasDiskChanged(relativeTo: url) {
            hasExternalConflict = true
            conflictDeferred = false
            return false
        }

        return writeToDisk(url, force: force)
    }

    /// Discard the in-memory buffer and re-read from disk (Reload Theirs).
    @discardableResult
    func reloadFromDisk() -> Bool {
        guard let url = fileURL else { return false }
        saveTask?.cancel()
        saveTask = nil
        guard let (readText, snapshot) = Self.readTextAndSnapshot(of: url) else {
            hasExternalConflict = false
            if !FileManager.default.fileExists(atPath: url.path) {
                hasMissingFile = true
                lastSaveFailed = true
            }
            lastError = (.openNote, CocoaError(.fileReadUnknown))
            return false
        }
        text = readText
        isDirty = false
        lastError = nil
        lastSaveFailed = false
        hasExternalConflict = false
        hasMissingFile = false
        conflictDeferred = false
        diskSnapshot = snapshot
        refreshFileDates(for: url, markSavedNow: false)
        return true
    }

    private func writeToDisk(_ url: URL, force: Bool) -> Bool {
        do {
            // Ensure parent exists when force-recreating after a move/delete.
            let parent = url.deletingLastPathComponent()
            guard !FileSystemVault.hasSymlink(parent), !FileSystemVault.hasSymlink(url) else {
                throw CocoaError(.fileWriteNoPermission)
            }
            if let vaultRoot, !FileSystemVault.isSafePath(url, within: vaultRoot) {
                throw CocoaError(.fileWriteNoPermission)
            }
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            var coordinationError: NSError?
            var writeError: Error?
            var didWrite = false
            var detectedConflict = false
            let itemExists = FileManager.default.fileExists(atPath: url.path)
            let options: NSFileCoordinator.WritingOptions = itemExists ? .forReplacing : []

            // Always coordinate. The old uncoordinated "file missing" fast path
            // could recreate or clobber a file that appeared between the
            // existence check and the write.
            NSFileCoordinator(filePresenter: nil).coordinate(
                writingItemAt: url,
                options: options,
                error: &coordinationError
            ) { coordinatedURL in
                if FileSystemVault.hasSymlink(url) || FileSystemVault.hasSymlink(parent) {
                    writeError = CocoaError(.fileWriteNoPermission)
                    return
                }
                if let vaultRoot, !FileSystemVault.isSafePath(url, within: vaultRoot) {
                    writeError = CocoaError(.fileWriteNoPermission)
                    return
                }
                if let vaultRoot, !FileSystemVault.isSafePath(parent, within: vaultRoot) {
                    writeError = CocoaError(.fileWriteNoPermission)
                    return
                }
                let coordinatedExists = FileManager.default.fileExists(atPath: coordinatedURL.path)
                if !force {
                    if !coordinatedExists {
                        hasMissingFile = true
                        lastSaveFailed = true
                        detectedConflict = true
                        return
                    }
                    guard let known = diskSnapshot, known.path == url.path else {
                        detectedConflict = true
                        return
                    }
                    guard let current = Self.captureSnapshot(of: coordinatedURL) else {
                        hasMissingFile = true
                        lastSaveFailed = true
                        detectedConflict = true
                        return
                    }
                    guard current.hasSameFileIdentity(as: known) else {
                        hasExternalConflict = true
                        conflictDeferred = false
                        detectedConflict = true
                        return
                    }
                }

                do {
                    // Ensure parent still exists inside the coordinated block for force-recreate.
                    if force, !FileManager.default.fileExists(atPath: parent.path) {
                        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                        if let vaultRoot, !FileSystemVault.isSafePath(parent, within: vaultRoot) {
                            throw CocoaError(.fileWriteNoPermission)
                        }
                        guard !FileSystemVault.hasSymlink(parent) else {
                            throw CocoaError(.fileWriteNoPermission)
                        }
                    }
                    try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                    if let vaultRoot, !FileSystemVault.isSafePath(coordinatedURL, within: vaultRoot) {
                        writeError = CocoaError(.fileWriteNoPermission)
                        return
                    }
                    // Verify the bytes just written are still the buffer we wrote.
                    // Otherwise another writer replaced the file between the write
                    // and the new clean snapshot.
                    let expected = text.data(using: .utf8) ?? Data()
                    guard let current = Self.captureSnapshot(of: coordinatedURL),
                          current.content == expected else {
                        if !FileManager.default.fileExists(atPath: coordinatedURL.path) {
                            hasMissingFile = true
                            lastSaveFailed = true
                        } else {
                            hasExternalConflict = true
                            conflictDeferred = false
                        }
                        detectedConflict = true
                        return
                    }
                    diskSnapshot = current
                    didWrite = true
                } catch {
                    writeError = error
                }
            }

            if detectedConflict {
                if !hasMissingFile {
                    hasExternalConflict = true
                    conflictDeferred = false
                }
                return false
            }
            guard didWrite else {
                throw coordinationError ?? writeError ?? CocoaError(.fileWriteUnknown)
            }
            isDirty = false
            lastError = nil
            lastSaveFailed = false
            hasExternalConflict = false
            hasMissingFile = false
            conflictDeferred = false
            refreshFileDates(for: url, markSavedNow: true)
            return true
        } catch {
            // Leave dirty so user can retry with ⌘S.
            lastError = (.saveNote, error)
            lastSaveFailed = true
            return false
        }
    }

    private func clearBuffer() {
        saveTask?.cancel()
        saveTask = nil
        fileURL = nil
        text = ""
        isDirty = false
        diskSnapshot = nil
        hasExternalConflict = false
        hasMissingFile = false
        conflictDeferred = false
        lastError = nil
        lastSaveFailed = false
        createdAt = nil
        lastSavedAt = nil
    }

    /// Reads creation date; sets `lastSavedAt` to now after a write, else disk mtime.
    private func refreshFileDates(for url: URL, markSavedNow: Bool) {
        var fresh = url
        fresh.removeCachedResourceValue(forKey: .creationDateKey)
        fresh.removeCachedResourceValue(forKey: .contentModificationDateKey)
        let values = try? fresh.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        createdAt = values?.creationDate
        if markSavedNow {
            lastSavedAt = Date()
        } else {
            lastSavedAt = values?.contentModificationDate
        }
    }

    private func hasDiskChanged(relativeTo url: URL) -> Bool {
        guard let known = diskSnapshot, known.path == url.path else { return true }
        guard let current = Self.captureSnapshot(of: url) else { return true }
        return !current.hasSameFileIdentity(as: known)
    }

    private func rememberDiskSnapshot(for url: URL) {
        diskSnapshot = Self.captureSnapshot(of: url)
    }

    nonisolated static func modificationDate(of url: URL) -> Date? {
        fileIdentity(of: url)?.date
    }

    nonisolated static func fileIdentity(of url: URL) -> (date: Date, size: Int)? {
        guard let metadata = metadata(of: url) else { return nil }
        return (metadata.date, metadata.size)
    }

    private nonisolated static func metadata(of url: URL) -> FileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            return nil
        }
        let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        return FileMetadata(date: date, size: size, device: device, inode: inode)
    }

    /// Reads UTF-8 text and its snapshot from one coherent byte read, so the
    /// buffer and conflict identity cannot describe different disk versions.
    nonisolated static func readTextAndSnapshot(of url: URL) -> (String, DiskSnapshot?)? {
        for _ in 0..<2 {
            guard let before = metadata(of: url),
                  let content = try? Data(contentsOf: url),
                  let after = metadata(of: url),
                  before == after,
                  let text = String(data: content, encoding: .utf8) else {
                continue
            }
            let snapshot = DiskSnapshot(
                path: url.path,
                date: after.date,
                size: after.size,
                device: after.device,
                inode: after.inode,
                content: content
            )
            return (text, snapshot)
        }
        return nil
    }

    private nonisolated static func captureSnapshot(of url: URL) -> DiskSnapshot? {
        // Retry once if metadata changes while the bytes are being read so the
        // saved identity cannot combine one version's metadata with another's.
        // Note: This performs blocking I/O (attributes + Data read). Callers on
        // @MainActor should keep notes small; large vaults rely on the detached
        // scan in VaultStore, not this per-save path.
        for _ in 0..<2 {
            guard let before = metadata(of: url),
                  let content = try? Data(contentsOf: url),
                  let after = metadata(of: url),
                  before == after else {
                continue
            }
            return DiskSnapshot(
                path: url.path,
                date: after.date,
                size: after.size,
                device: after.device,
                inode: after.inode,
                content: content
            )
        }
        return nil
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = nil
        // Suspend while the user has deferred a conflict; explicit ⌘S still saves.
        guard !conflictDeferred else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            _ = self?.saveIfNeeded()
        }
    }
}
