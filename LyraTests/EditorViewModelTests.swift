import XCTest
@testable import Lyra

@MainActor
final class EditorViewModelTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    /// Point the dirty buffer at a directory path so `write(to:atomically:)` fails reliably
    /// (chmod on a file alone does not block atomic replace when the parent dir is writable).
    private func makeUnwritableSaveTarget() throws -> URL {
        let blocker = tempRoot.appendingPathComponent("not-a-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        return blocker
    }

    func testOpenPreservesBufferWhenSaveFails() throws {
        let a = tempRoot.appendingPathComponent("a.md")
        let b = tempRoot.appendingPathComponent("b.md")
        try "original-a".write(to: a, atomically: true, encoding: .utf8)
        try "content-b".write(to: b, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "unsaved edits"
        editor.isDirty = true
        let blocked = try makeUnwritableSaveTarget()
        editor.fileURL = blocked

        XCTAssertFalse(editor.open(url: b))
        XCTAssertEqual(editor.text, "unsaved edits")
        XCTAssertEqual(editor.fileURL?.path, blocked.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertNotNil(editor.lastError)
        XCTAssertEqual(editor.lastError?.context, .saveNote)
    }

    func testClosePreservesBufferWhenSaveFails() throws {
        let a = tempRoot.appendingPathComponent("close-me.md")
        try "stay".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "dirty"
        editor.isDirty = true
        let blocked = try makeUnwritableSaveTarget()
        editor.fileURL = blocked

        XCTAssertFalse(editor.close())
        XCTAssertEqual(editor.text, "dirty")
        XCTAssertEqual(editor.fileURL?.path, blocked.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertNotNil(editor.lastError)
    }

    func testOpenSucceedsAfterCleanSave() throws {
        let a = tempRoot.appendingPathComponent("clean-a.md")
        let b = tempRoot.appendingPathComponent("clean-b.md")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "a-updated"
        editor.isDirty = true

        XCTAssertTrue(editor.open(url: b))
        XCTAssertEqual(editor.text, "b")
        XCTAssertEqual(editor.fileURL?.path, b.path)
        XCTAssertFalse(editor.isDirty)
        XCTAssertNil(editor.lastError)

        let diskA = try String(contentsOf: a, encoding: .utf8)
        XCTAssertEqual(diskA, "a-updated")
    }
}
