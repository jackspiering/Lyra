import Foundation
import Observation

@MainActor
@Observable
final class EditorViewModel {
    var fileURL: URL?
    var text: String = ""
    var isDirty = false
    /// Last save/open failure for the UI to present.
    var lastError: (context: UserFacingError.Context, error: Error)?
    /// Disk mtime/size changed under us while dirty — UI offers Keep Mine / Reload.
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

    /// Path + mtime + size observed at last successful open/save/reload.
    private var diskSnapshot: (path: String, date: Date, size: Int)?
    private var saveTask: Task<Void, Never>?

    /// Opens `url` after flushing dirty state. Returns `false` if a dirty save failed;
    /// in that case `text` / `fileURL` / `isDirty` are left unchanged so the user can retry.
    @discardableResult
    func open(url: URL) -> Bool {
        guard saveIfNeeded() else { return false }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            isDirty = false
            lastError = nil
            lastSaveFailed = false
            hasExternalConflict = false
            hasMissingFile = false
            conflictDeferred = false
            rememberDiskSnapshot(for: url)
            refreshFileDates(for: url, markSavedNow: false)
            return true
        } catch {
            fileURL = nil
            text = ""
            isDirty = false
            diskSnapshot = nil
            createdAt = nil
            lastSavedAt = nil
            lastError = (.openNote, error)
            return false
        }
    }

    /// Point the editor at a new path without saving (e.g. after rename).
    func relocate(to newURL: URL) {
        saveTask?.cancel()
        saveTask = nil
        fileURL = newURL
        hasMissingFile = false
        hasExternalConflict = false
        conflictDeferred = false
        rememberDiskSnapshot(for: newURL)
        refreshFileDates(for: newURL, markSavedNow: false)
    }

    /// Cancel on the conflict dialog: stop autosaving without treating Cancel as overwrite.
    func deferConflict() {
        hasExternalConflict = false
        conflictDeferred = true
        saveTask?.cancel()
        saveTask = nil
    }

    /// Closes the current note after flushing dirty state. Returns `false` if save failed.
    /// Closing still succeeds when the file or its parent no longer exists so the user is not trapped.
    @discardableResult
    func close() -> Bool {
        if isDirty, let url = fileURL, !FileManager.default.fileExists(atPath: url.path) {
            // Cannot save a missing path; abandon the buffer rather than trap the UI.
            clearBuffer()
            return true
        }
        guard saveIfNeeded() else { return false }
        clearBuffer()
        return true
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
                return writeToDisk(url)
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

        return writeToDisk(url)
    }

    /// Discard the in-memory buffer and re-read from disk (Reload Theirs).
    @discardableResult
    func reloadFromDisk() -> Bool {
        guard let url = fileURL else { return false }
        saveTask?.cancel()
        saveTask = nil
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            isDirty = false
            lastError = nil
            lastSaveFailed = false
            hasExternalConflict = false
            hasMissingFile = false
            conflictDeferred = false
            rememberDiskSnapshot(for: url)
            refreshFileDates(for: url, markSavedNow: false)
            return true
        } catch {
            lastError = (.openNote, error)
            return false
        }
    }

    private func writeToDisk(_ url: URL) -> Bool {
        do {
            // Ensure parent exists when force-recreating after a move/delete.
            let parent = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            lastError = nil
            lastSaveFailed = false
            hasExternalConflict = false
            hasMissingFile = false
            conflictDeferred = false
            rememberDiskSnapshot(for: url)
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
        guard let known = diskSnapshot, known.path == url.path else { return false }
        guard let current = Self.fileIdentity(of: url) else { return false }
        if abs(current.date.timeIntervalSince(known.date)) > 0.001 { return true }
        if current.size != known.size { return true }
        return false
    }

    private func rememberDiskSnapshot(for url: URL) {
        if let id = Self.fileIdentity(of: url) {
            diskSnapshot = (url.path, id.date, id.size)
        } else {
            diskSnapshot = nil
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        fileIdentity(of: url)?.date
    }

    static func fileIdentity(of url: URL) -> (date: Date, size: Int)? {
        // Resource values are cached on the URL; always re-stat for conflict checks.
        var fresh = url
        fresh.removeCachedResourceValue(forKey: .contentModificationDateKey)
        fresh.removeCachedResourceValue(forKey: .fileSizeKey)
        let values = try? fresh.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let date = values?.contentModificationDate else { return nil }
        let size = values?.fileSize ?? 0
        return (date, size)
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
