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

    func open(url: URL) {
        _ = saveIfNeeded()
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            isDirty = false
            lastError = nil
        } catch {
            fileURL = nil
            text = ""
            isDirty = false
            lastError = (.openNote, error)
        }
    }

    func close() {
        _ = saveIfNeeded()
        fileURL = nil
        text = ""
        isDirty = false
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
