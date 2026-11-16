import XCTest
@testable import Lyra

final class VaultStoreRenameTests: XCTestCase {
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

    @MainActor
    func testRenameFlowUpdatesLinksInOpenAndClosedNotes() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Old.md")
        let closed = root.appendingPathComponent("Closed.md")
        let open = root.appendingPathComponent("Open.md")
        let unrelated = root.appendingPathComponent("Unrelated.md")
        try "target".write(to: old, atomically: true, encoding: .utf8)
        try "See [[Old]] and [[Old|the plan]].".write(to: closed, atomically: true, encoding: .utf8)
        try "Also [[Old]].".write(to: open, atomically: true, encoding: .utf8)
        try "Code only: `[[Old]]`.".write(to: unrelated, atomically: true, encoding: .utf8)
        let store = try openedStore(at: root)
        let tabs = NoteTabController()
        let openNode = try XCTUnwrap(store.node(withID: open.path))
        XCTAssertTrue(tabs.openInActiveTab(url: openNode.url))
        let flow = RenameFlow(store: store, tabs: tabs, flushError: { _ in })
        let oldNode = try XCTUnwrap(store.node(withID: old.path))

        XCTAssertTrue(flow.rename(oldNode, to: "New"))

        let update = try XCTUnwrap(flow.pendingLinkUpdate)
        XCTAssertEqual(update.newStem, "New")
        XCTAssertEqual(
            update.sources.map(\.url.lastPathComponent).sorted(),
            ["Closed.md", "Open.md"]
        )

        flow.applyLinkUpdate(update)

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("New.md").path))
        // A closed note is rewritten on disk; folder paths and aliases are kept.
        XCTAssertEqual(
            try String(contentsOf: closed, encoding: .utf8),
            "See [[New]] and [[New|the plan]]."
        )
        // An open note changes in its tab and saves through the normal path.
        XCTAssertEqual(tabs.selectedEditor.text, "Also [[New]].")
        XCTAssertTrue(tabs.selectedEditor.isDirty)
        XCTAssertTrue(tabs.selectedEditor.saveIfNeeded())
        XCTAssertEqual(try String(contentsOf: open, encoding: .utf8), "Also [[New]].")
        // A link inside code is not a link.
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "Code only: `[[Old]]`.")
    }

    @MainActor
    func testRenameFlowLeavesLinksAloneUntilConfirmed() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Old.md")
        let linking = root.appendingPathComponent("Linking.md")
        let lonely = root.appendingPathComponent("Lonely.md")
        try "target".write(to: old, atomically: true, encoding: .utf8)
        try "See [[Old]].".write(to: linking, atomically: true, encoding: .utf8)
        try "nobody links here".write(to: lonely, atomically: true, encoding: .utf8)
        let store = try openedStore(at: root)
        let tabs = NoteTabController()
        let flow = RenameFlow(store: store, tabs: tabs, flushError: { _ in })

        // Nothing links to Lonely: no question is asked.
        let lonelyNode = try XCTUnwrap(store.node(withID: lonely.path))
        XCTAssertTrue(flow.rename(lonelyNode, to: "Alone"))
        XCTAssertNil(flow.pendingLinkUpdate)

        // Old is linked: the rename asks, and nothing is rewritten before the answer.
        let oldNode = try XCTUnwrap(store.node(withID: old.path))
        XCTAssertTrue(flow.rename(oldNode, to: "New"))
        XCTAssertNotNil(flow.pendingLinkUpdate)
        XCTAssertEqual(try String(contentsOf: linking, encoding: .utf8), "See [[Old]].")
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
