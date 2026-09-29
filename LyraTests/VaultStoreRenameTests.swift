import XCTest
@testable import Lyra

final class VaultStoreRenameTests: XCTestCase {
    func testRejectsEmpty() {
        switch FilenameValidation.validate("   ", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid(let msg): XCTAssertTrue(msg.contains("empty"))
        }
    }

    func testRejectsPathSeparators() {
        switch FilenameValidation.validate("a/b.md", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid: break
        }
        switch FilenameValidation.validate("a:b.md", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid: break
        }
    }

    func testRejectsLeadingDot() {
        switch FilenameValidation.validate(".hidden.md", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid: break
        }
    }

    func testAppendsMarkdownExtensionForFiles() {
        XCTAssertEqual(FilenameValidation.validate("Note", isDirectory: false), .ok("Note.md"))
        XCTAssertEqual(FilenameValidation.validate("Note.md", isDirectory: false), .ok("Note.md"))
        XCTAssertEqual(FilenameValidation.validate("Note.MD", isDirectory: false), .ok("Note.MD"))
    }

    func testFoldersKeepNameWithoutMd() {
        XCTAssertEqual(FilenameValidation.validate("Projects", isDirectory: true), .ok("Projects"))
    }

    @MainActor
    func testLargeNotesExcludedFromSearchAndBacklinks() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let small = root.appendingPathComponent("small.md")
        try "small target".write(to: small, atomically: true, encoding: .utf8)
        let large = root.appendingPathComponent("large.md")
        let filler = String(repeating: "large-target ", count: 200_000)
        try ("[[small]]\n" + filler).write(to: large, atomically: true, encoding: .utf8)

        let store = VaultStore()
        store.openVault(at: root)
        let deadline = Date().addingTimeInterval(5)
        while store.rootNode == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(store.scanSkippedLargeNotes)
        XCTAssertTrue(
            VaultFullTextSearch.search(documents: store.searchCorpus(liveBodies: [:]), query: "large-target").isEmpty
        )
        XCTAssertTrue(store.backlinks(to: small, liveBodies: [:]).isEmpty)
        // Left out of the indexes, but still a note: a link to it must not offer Create.
        guard case .unique(let resolved) = store.resolveWikiLink("large") else {
            return XCTFail("expected [[large]] to resolve")
        }
        XCTAssertEqual(resolved.lastPathComponent, "large.md")
    }

    @MainActor
    func testRenameReturnsDestinationImmediately() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let note = root.appendingPathComponent("alpha.md")
        try "hi".write(to: note, atomically: true, encoding: .utf8)

        let store = VaultStore()
        store.openVault(at: root)
        // Wait briefly for the initial scan so the note is in the tree.
        let deadline = Date().addingTimeInterval(2)
        while store.rootNode == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        // The destination comes back before the rescan that shows it lands.
        let dest = try XCTUnwrap(store.renameItem(at: note, to: "beta.md"))
        XCTAssertEqual(dest.lastPathComponent, "beta.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }

    @MainActor
    func testUntitledCreateSucceedsWithoutCollisionError() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try openedStore(at: root)

        XCTAssertTrue(store.createNote(named: nil))
        XCTAssertNil(store.errorMessage)
        let stem = GeneralPreferences.defaultNoteStem
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(stem).md").path))
    }

    @MainActor
    func testRenameToSameNameWithoutExtensionIsNoOp() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("alpha.md")
        try "hi".write(to: note, atomically: true, encoding: .utf8)
        let store = try openedStore(at: root)

        let dest = try XCTUnwrap(store.renameItem(at: note, to: "alpha"))
        XCTAssertEqual(dest.lastPathComponent, "alpha.md")
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path))
    }

    @MainActor
    func testRenameItemDoesNotMoveSelectionFirst() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("alpha.md")
        try "hi".write(to: note, atomically: true, encoding: .utf8)
        let store = try openedStore(at: root)
        store.selection = nil

        let dest = try XCTUnwrap(store.renameItem(at: note, to: "beta"))
        XCTAssertEqual(dest.lastPathComponent, "beta.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        // The old path must never be selected: that would try to open a moved file.
        XCTAssertNil(store.selection)
    }

    private func makeTempVault() throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
    }

    @MainActor
    private func openedStore(at root: URL) throws -> VaultStore {
        let store = VaultStore()
        store.openVault(at: root)
        let deadline = Date().addingTimeInterval(5)
        while store.rootNode == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        _ = try XCTUnwrap(store.rootNode)
        return store
    }
}
