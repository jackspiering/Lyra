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

    func testOpenPreservesBufferWhenSaveFails() throws {
        // Parent directory becomes non-writable so atomic write fails without
        // reassigning fileURL (which would trip the external-mtime check).
        let roDir = tempRoot.appendingPathComponent("ro", isDirectory: true)
        try FileManager.default.createDirectory(at: roDir, withIntermediateDirectories: true)
        let a = roDir.appendingPathComponent("a.md")
        let b = tempRoot.appendingPathComponent("b.md")
        try "original-a".write(to: a, atomically: true, encoding: .utf8)
        try "content-b".write(to: b, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "unsaved edits"
        editor.isDirty = true

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        }

        XCTAssertFalse(editor.open(url: b))
        XCTAssertEqual(editor.text, "unsaved edits")
        XCTAssertEqual(editor.fileURL?.path, a.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertFalse(editor.hasExternalConflict)
        XCTAssertNotNil(editor.lastError)
        XCTAssertEqual(editor.lastError?.context, .saveNote)
    }

    func testClosePreservesBufferWhenSaveFails() throws {
        let roDir = tempRoot.appendingPathComponent("ro-close", isDirectory: true)
        try FileManager.default.createDirectory(at: roDir, withIntermediateDirectories: true)
        let a = roDir.appendingPathComponent("close-me.md")
        try "stay".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "dirty"
        editor.isDirty = true

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        }

        XCTAssertFalse(editor.close())
        XCTAssertEqual(editor.text, "dirty")
        XCTAssertEqual(editor.fileURL?.path, a.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertFalse(editor.hasExternalConflict)
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

    func testSaveBlockedWhenDiskChangedExternally() throws {
        let a = tempRoot.appendingPathComponent("ext.md")
        try "mine".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        let known = try XCTUnwrap(EditorViewModel.modificationDate(of: a))

        editor.text = "local edits"
        editor.isDirty = true

        try "theirs".write(to: a, atomically: true, encoding: .utf8)
        // Force mtime strictly after the value recorded at open (1s FS resolution).
        let future = known.addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: a.path)
        let current = try XCTUnwrap(EditorViewModel.modificationDate(of: a))
        XCTAssertGreaterThan(current.timeIntervalSince(known), 0.001)

        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.hasExternalConflict)
        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(editor.text, "local edits")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "theirs")

        XCTAssertTrue(editor.saveIfNeeded(force: true))
        XCTAssertFalse(editor.hasExternalConflict)
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "local edits")
    }

    func testReloadFromDiskDiscardsLocalEdits() throws {
        let a = tempRoot.appendingPathComponent("reload.md")
        try "disk".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "local"
        editor.isDirty = true
        try "updated-on-disk".write(to: a, atomically: true, encoding: .utf8)

        XCTAssertTrue(editor.reloadFromDisk())
        XCTAssertEqual(editor.text, "updated-on-disk")
        XCTAssertFalse(editor.isDirty)
        XCTAssertFalse(editor.hasExternalConflict)
    }

    func testRelocateUpdatesPathWithoutSaving() throws {
        let a = tempRoot.appendingPathComponent("old.md")
        let b = tempRoot.appendingPathComponent("new.md")
        try "body".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "edited"
        editor.isDirty = true
        editor.relocate(to: b)
        XCTAssertEqual(editor.fileURL?.path, b.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(editor.text, "edited")
        // Old path must not be recreated until an explicit save to the new path.
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    func testCloseSucceedsWhenParentDirectoryRemoved() throws {
        let dir = tempRoot.appendingPathComponent("gone", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("note.md")
        try "x".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "dirty"
        editor.isDirty = true
        try FileManager.default.removeItem(at: dir)

        XCTAssertTrue(editor.close())
        XCTAssertNil(editor.fileURL)
        XCTAssertFalse(editor.isDirty)
    }

    func testBackdatedExternalWriteIsDetected() throws {
        let a = tempRoot.appendingPathComponent("backdate.md")
        try "mine".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        let known = try XCTUnwrap(EditorViewModel.modificationDate(of: a))

        editor.text = "local"
        editor.isDirty = true

        try "theirs".write(to: a, atomically: true, encoding: .utf8)
        let past = known.addingTimeInterval(-30)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: a.path)

        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.hasExternalConflict)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "theirs")
    }

    func testDeletedFileDoesNotRecreateOnAutosave() throws {
        let a = tempRoot.appendingPathComponent("deleted.md")
        try "mine".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "local"
        editor.isDirty = true
        try FileManager.default.removeItem(at: a)

        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.hasMissingFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))

        XCTAssertTrue(editor.saveIfNeeded(force: true))
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "local")
    }

    func testConflictDeferSuspendsAutosave() throws {
        let a = tempRoot.appendingPathComponent("defer.md")
        try "mine".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        let known = try XCTUnwrap(EditorViewModel.modificationDate(of: a))
        editor.text = "local"
        editor.isDirty = true
        try "theirs".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: known.addingTimeInterval(5)],
            ofItemAtPath: a.path
        )
        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.hasExternalConflict)

        editor.deferConflict()
        XCTAssertTrue(editor.conflictDeferred)
        editor.noteEdited()
        // Autosave is suspended; disk still has "theirs".
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "theirs")

        XCTAssertTrue(editor.saveIfNeeded(force: true))
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "local")
        XCTAssertFalse(editor.conflictDeferred)
    }

    func testFailedSaveLeavesDirtyAndError() throws {
        let roDir = tempRoot.appendingPathComponent("ro-fail", isDirectory: true)
        try FileManager.default.createDirectory(at: roDir, withIntermediateDirectories: true)
        let a = roDir.appendingPathComponent("note.md")
        try "x".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "dirty"
        editor.isDirty = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        }

        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.isDirty)
        XCTAssertTrue(editor.lastSaveFailed)
        XCTAssertNotNil(editor.lastError)
        XCTAssertTrue(editor.hasError)
    }
}
