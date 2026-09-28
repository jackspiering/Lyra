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

        // Lock both the folder and the file so neither a replace nor an
        // in-place write can succeed.
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: a.path)
        }

        XCTAssertFalse(editor.open(url: b))
        XCTAssertEqual(editor.text, "unsaved edits")
        XCTAssertEqual(editor.fileURL?.path, a.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertFalse(editor.hasExternalConflict)
        XCTAssertNotNil(editor.lastError)
        XCTAssertEqual(editor.lastError?.context, .saveNote)
    }

    func testOpenPreservesActiveBufferWhenTargetCannotBeRead() throws {
        let active = tempRoot.appendingPathComponent("active.md")
        let unreadable = tempRoot.appendingPathComponent("invalid-utf8.md")
        try "keep this buffer".write(to: active, atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE]).write(to: unreadable)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: active))

        XCTAssertFalse(editor.open(url: unreadable))
        XCTAssertEqual(editor.fileURL?.path, active.path)
        XCTAssertEqual(editor.text, "keep this buffer")
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.lastError?.context, .openNote)
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

    func testReloadMissingFileOffersMissingFileRecovery() throws {
        let a = tempRoot.appendingPathComponent("reload-missing.md")
        try "disk".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "local"
        editor.isDirty = true
        editor.hasExternalConflict = true
        try FileManager.default.removeItem(at: a)

        XCTAssertFalse(editor.reloadFromDisk())
        XCTAssertTrue(editor.hasMissingFile)
        XCTAssertFalse(editor.hasExternalConflict)
        XCTAssertEqual(editor.text, "local")
        XCTAssertTrue(editor.isDirty)
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

    func testCloseBlocksWhenParentDirectoryRemoved() throws {
        let dir = tempRoot.appendingPathComponent("gone", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("note.md")
        try "x".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "dirty"
        editor.isDirty = true
        try FileManager.default.removeItem(at: dir)

        XCTAssertFalse(editor.close())
        XCTAssertEqual(editor.fileURL?.path, a.path)
        XCTAssertEqual(editor.text, "dirty")
        XCTAssertTrue(editor.isDirty)
        XCTAssertTrue(editor.hasMissingFile)

        editor.discardAndClose()
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

    func testSameSizeReplacementWithOriginalMtimeIsDetected() throws {
        let a = tempRoot.appendingPathComponent("same-identity.md")
        try "mine".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        let known = try XCTUnwrap(EditorViewModel.modificationDate(of: a))

        editor.text = "local"
        editor.isDirty = true
        try "thei".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: known], ofItemAtPath: a.path)

        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.hasExternalConflict)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "thei")
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

    func testForceSaveRejectsSymlinkedParent() throws {
        let dir = tempRoot.appendingPathComponent("redirected", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let note = dir.appendingPathComponent("note.md")
        try "original".write(to: note, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: note))
        editor.text = "local"
        editor.isDirty = true

        try FileManager.default.removeItem(at: dir)
        let outside = tempRoot.deletingLastPathComponent()
            .appendingPathComponent("lyra-redirect-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: dir, withDestinationURL: outside)

        XCTAssertFalse(editor.saveIfNeeded(force: true))
        XCTAssertTrue(editor.isDirty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("note.md").path))
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

    func testExplicitSaveWhileDeferredResurfacesConflict() throws {
        let a = tempRoot.appendingPathComponent("defer-explicit.md")
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
        editor.deferConflict()
        XCTAssertTrue(editor.conflictDeferred)

        // The ⌘S path is a non-force save: it must not silently overwrite
        // "theirs" while a conflict is deferred. It re-checks disk identity
        // and clears the deferral so the conflict dialog can reappear.
        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertFalse(editor.conflictDeferred)
        XCTAssertTrue(editor.hasExternalConflict)
        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(editor.text, "local")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "theirs")
    }

    func testLastSaveFailedClearsOnSuccessfulSave() throws {
        let roDir = tempRoot.appendingPathComponent("ro-recover", isDirectory: true)
        try FileManager.default.createDirectory(at: roDir, withIntermediateDirectories: true)
        let a = roDir.appendingPathComponent("note.md")
        try "x".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "dirty"
        editor.isDirty = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.lastSaveFailed)
        XCTAssertTrue(editor.hasError)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        XCTAssertTrue(editor.saveIfNeeded())
        // Sticky failure state clears only on a successful write.
        XCTAssertFalse(editor.lastSaveFailed)
        XCTAssertNil(editor.lastError)
        XCTAssertFalse(editor.hasError)
    }

    func testNoteEditedTracksOnlyOpenFiles() throws {
        let editor = EditorViewModel()
        editor.noteEdited()
        XCTAssertFalse(editor.isDirty)

        let a = tempRoot.appendingPathComponent("edited.md")
        try "x".write(to: a, atomically: true, encoding: .utf8)
        XCTAssertTrue(editor.open(url: a))
        editor.text = "changed"
        editor.noteEdited()
        XCTAssertTrue(editor.isDirty)
    }

    func testSyncReloadsCleanBufferAfterExternalEdit() throws {
        let a = tempRoot.appendingPathComponent("sync-clean.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))

        try "changed elsewhere".write(to: a, atomically: true, encoding: .utf8)
        editor.syncWithDiskIfClean()

        XCTAssertEqual(editor.text, "changed elsewhere")
        XCTAssertFalse(editor.isDirty)
        XCTAssertFalse(editor.hasExternalConflict)
    }

    func testSyncLeavesDirtyBufferAlone() throws {
        let a = tempRoot.appendingPathComponent("sync-dirty.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "mine"
        editor.isDirty = true

        try "theirs".write(to: a, atomically: true, encoding: .utf8)
        editor.syncWithDiskIfClean()

        XCTAssertEqual(editor.text, "mine")
        XCTAssertTrue(editor.isDirty)
        XCTAssertFalse(editor.hasExternalConflict)
    }

    func testSyncFlagsMissingFileForCleanBuffer() throws {
        let a = tempRoot.appendingPathComponent("sync-missing.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))

        try FileManager.default.removeItem(at: a)
        editor.syncWithDiskIfClean()
        XCTAssertTrue(editor.hasMissingFile)

        // Save Here recreates the note even though the buffer is clean.
        XCTAssertTrue(editor.saveIfNeeded(force: true))
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "original")
        XCTAssertFalse(editor.hasMissingFile)
    }

    func testSyncDoesNotResurfaceDeferredMissingFile() throws {
        let a = tempRoot.appendingPathComponent("sync-deferred.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        try FileManager.default.removeItem(at: a)
        editor.syncWithDiskIfClean()
        editor.deferConflict()
        editor.hasMissingFile = false

        editor.syncWithDiskIfClean()
        XCTAssertFalse(editor.hasMissingFile)
    }

    func testSaveUnlessDeferredKeepsConflictDeferred() throws {
        let a = tempRoot.appendingPathComponent("lifecycle.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "mine"
        editor.isDirty = true
        try "theirs".write(to: a, atomically: true, encoding: .utf8)

        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertTrue(editor.hasExternalConflict)
        editor.deferConflict()

        // App switch: must not re-raise the dialog or touch disk.
        XCTAssertTrue(editor.saveUnlessDeferred())
        XCTAssertFalse(editor.hasExternalConflict)
        XCTAssertTrue(editor.conflictDeferred)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "theirs")
    }

    func testSavePreservesCreationDate() throws {
        let a = tempRoot.appendingPathComponent("created.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let past = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
        try FileManager.default.setAttributes([.creationDate: past], ofItemAtPath: a.path)
        guard let before = try FileManager.default.attributesOfItem(atPath: a.path)[.creationDate] as? Date,
              abs(before.timeIntervalSince(past)) < 1 else {
            throw XCTSkip("Filesystem does not support creation dates")
        }

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "edited"
        editor.isDirty = true
        XCTAssertTrue(editor.saveIfNeeded())

        let after = try FileManager.default.attributesOfItem(atPath: a.path)[.creationDate] as? Date
        XCTAssertEqual(after?.timeIntervalSince1970 ?? 0, past.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "edited")
    }

    func testSecondSaveAfterSaveIsNotAConflict() throws {
        let a = tempRoot.appendingPathComponent("twice.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)
        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "one"
        editor.isDirty = true
        XCTAssertTrue(editor.saveIfNeeded())
        editor.text = "two"
        editor.isDirty = true
        XCTAssertTrue(editor.saveIfNeeded())
        XCTAssertFalse(editor.hasExternalConflict)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "two")
    }

    func testAutosavePersistsEditsAfterDebounce() async throws {
        let a = tempRoot.appendingPathComponent("autosave.md")
        try "original".write(to: a, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "autosaved"
        editor.noteEdited()

        // Poll instead of sleeping a fixed debounce: CI boxes are slow, and
        // awaiting keeps the main actor free so the debounced task can run.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (try? String(contentsOf: a, encoding: .utf8)) == "autosaved" {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "autosaved")
        XCTAssertFalse(editor.isDirty)
        XCTAssertNil(editor.lastError)
    }

    func testCoherentReadReturnsMatchingTextAndSnapshot() throws {
        let a = tempRoot.appendingPathComponent("coherent.md")
        try "coherent body".write(to: a, atomically: true, encoding: .utf8)

        let read = try XCTUnwrap(EditorViewModel.readTextAndSnapshot(of: a))
        XCTAssertEqual(read.0, "coherent body")
        XCTAssertEqual(read.1?.content, "coherent body".data(using: .utf8))

        let invalid = tempRoot.appendingPathComponent("invalid.md")
        try Data([0xFF, 0xFE]).write(to: invalid)
        XCTAssertNil(EditorViewModel.readTextAndSnapshot(of: invalid))
    }

    func testRelocateClearsPreviousSaveError() throws {
        let roDir = tempRoot.appendingPathComponent("ro-relocate", isDirectory: true)
        try FileManager.default.createDirectory(at: roDir, withIntermediateDirectories: true)
        let a = roDir.appendingPathComponent("relocate-old.md")
        let b = tempRoot.appendingPathComponent("relocate-new.md")
        try "body".write(to: a, atomically: true, encoding: .utf8)
        try "body".write(to: b, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
        XCTAssertTrue(editor.open(url: a))
        editor.text = "edited"
        editor.isDirty = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        }
        XCTAssertFalse(editor.saveIfNeeded())
        XCTAssertNotNil(editor.lastError)

        editor.relocate(to: b)
        XCTAssertNil(editor.lastError)
        XCTAssertFalse(editor.lastSaveFailed)
    }
}
