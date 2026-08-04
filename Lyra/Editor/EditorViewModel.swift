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
            return true
        } catch {
            fileURL = nil
            text = ""
            isDirty = false
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
        return true
    }

    /// Call after `text` has already been updated (e.g. via Binding).
    func noteEdited() {
        guard fileURL != nil else { return }
        isDirty = true
        scheduleAutosave()
    }

    /// Writes if dirty. Returns `false` when a write was attempted and failed.
    @discardableResult
    func saveIfNeeded() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let url = fileURL else { return true }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            lastError = nil
            return true
        } catch {
            // Leave dirty so user can retry with ⌘S.
            lastError = (.saveNote, error)
            return false
        }
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
