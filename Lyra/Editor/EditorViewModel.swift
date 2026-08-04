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
    /// Disk mtime changed under us while dirty — UI offers Keep Mine / Reload.
    var hasExternalConflict = false

    /// Modification date observed at last successful open/save/reload.
    private var diskModificationDate: Date?
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
            hasExternalConflict = false
            diskModificationDate = Self.modificationDate(of: url)
            return true
        } catch {
            fileURL = nil
            text = ""
            isDirty = false
            diskModificationDate = nil
            lastError = (.openNote, error)
            return false
        }
    }

    /// Closes the current note after flushing dirty state. Returns `false` if save failed.
    @discardableResult
    func close() -> Bool {
        guard saveIfNeeded() else { return false }
        fileURL = nil
        text = ""
        isDirty = false
        diskModificationDate = nil
        hasExternalConflict = false
        return true
    }

    /// Call after `text` has already been updated (e.g. via Binding).
    func noteEdited() {
        guard fileURL != nil else { return }
        isDirty = true
        scheduleAutosave()
    }

    /// Writes if dirty. Returns `false` when a write was attempted and failed or was blocked
    /// by an external disk change (`hasExternalConflict` is set). Pass `force: true` to
    /// overwrite disk after the user chooses Keep Mine.
    @discardableResult
    func saveIfNeeded(force: Bool = false) -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let url = fileURL else { return true }

        if !force, hasDiskChanged(relativeTo: url) {
            hasExternalConflict = true
            return false
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            lastError = nil
            hasExternalConflict = false
            diskModificationDate = Self.modificationDate(of: url)
            return true
        } catch {
            // Leave dirty so user can retry with ⌘S.
            lastError = (.saveNote, error)
            return false
        }
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
            hasExternalConflict = false
            diskModificationDate = Self.modificationDate(of: url)
            return true
        } catch {
            lastError = (.openNote, error)
            return false
        }
    }

    private func hasDiskChanged(relativeTo url: URL) -> Bool {
        guard let known = diskModificationDate else { return false }
        guard let current = Self.modificationDate(of: url) else { return false }
        // Small epsilon: filesystem mtime resolution can be coarse.
        return current.timeIntervalSince(known) > 0.001
    }

    static func modificationDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            _ = self?.saveIfNeeded()
        }
    }
}
