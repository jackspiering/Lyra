import Foundation
import Observation

@MainActor
@Observable
final class EditorViewModel {
    var fileURL: URL?
    var text: String = ""
    var isDirty = false

    private var saveTask: Task<Void, Never>?

    func open(url: URL) {
        saveIfNeeded()
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            isDirty = false
        } catch {
            fileURL = nil
            text = ""
            isDirty = false
        }
    }

    func close() {
        saveIfNeeded()
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

    func saveIfNeeded() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let url = fileURL else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            // Leave dirty so user can retry with ⌘S.
        }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveIfNeeded()
        }
    }
}
