import Foundation
import Observation

@MainActor
@Observable
final class EditorViewModel {
    var document: NoteDocument?
    var text: String = ""

    private var saveTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64 = 500_000_000

    func open(url: URL) async {
        await saveIfNeeded()
        do {
            let content = try await Task.detached {
                try FileSystemVault.readUTF8(from: url)
            }.value
            document = NoteDocument(url: url, content: content, isDirty: false)
            text = content
        } catch {
            document = nil
            text = ""
        }
    }

    func close() async {
        await saveIfNeeded()
        document = nil
        text = ""
    }

    func textDidChange(_ newValue: String) {
        text = newValue
        guard document != nil else { return }
        document?.content = newValue
        document?.isDirty = true
        scheduleAutosave()
    }

    func saveIfNeeded() async {
        saveTask?.cancel()
        saveTask = nil
        guard var doc = document, doc.isDirty else { return }
        let content = text
        let url = doc.url
        do {
            try await Task.detached {
                try FileSystemVault.writeUTF8(content, to: url)
            }.value
            doc.content = content
            doc.isDirty = false
            document = doc
        } catch {
            // Leave dirty so user can retry with ⌘S.
        }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveIfNeeded()
        }
    }
}
