import XCTest
@testable import Lyra

@MainActor
final class NoteTabModelTests: XCTestCase {
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

    /// Writes a note into the temporary vault root and returns its URL.
    private func note(_ name: String, content: String = "content") throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Initial state

    func testInitKeepsSingleEmptyTabSelected() {
        let controller = NoteTabController()
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.selectedTabID, controller.tabs[0].id)
        XCTAssertNil(controller.selectedEditor.fileURL)
        XCTAssertEqual(controller.tabs[0].title, "New Tab")
        XCTAssertFalse(controller.anyDirty)
    }

    func testNewEmptyTabAppendsAndSelects() {
        let controller = NoteTabController()
        let firstID = controller.selectedTabID!
        let tab = controller.newEmptyTab()
        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertEqual(controller.selectedTabID, tab.id)
        XCTAssertNotEqual(tab.id, firstID)
        XCTAssertNil(tab.editor.fileURL)
    }

    func testAnyDirtyTracksEveryTab() throws {
        let controller = NoteTabController()
        let a = try note("a.md")
        XCTAssertTrue(controller.openInNewTab(url: a))
        XCTAssertFalse(controller.anyDirty)
        controller.tabs[1].editor.text = "unsaved edits"
        controller.tabs[1].editor.isDirty = true
        XCTAssertTrue(controller.anyDirty)
    }

    // MARK: - selectOpenNote

    func testSelectOpenNoteSelectsExistingTab() throws {
        let controller = NoteTabController()
        let a = try note("a.md")
        XCTAssertTrue(controller.openInNewTab(url: a))
        let aTabID = controller.selectedTabID!
        controller.select(controller.tabs[0].id)
        XCTAssertTrue(controller.selectOpenNote(path: a.path))
        XCTAssertEqual(controller.selectedTabID, aTabID)
    }

    func testSelectOpenNoteReturnsFalseAndKeepsSelectionWhenNotOpen() {
        let controller = NoteTabController()
        let originalID = controller.selectedTabID!
        XCTAssertFalse(controller.selectOpenNote(path: "/definitely/not/open.md"))
        XCTAssertEqual(controller.selectedTabID, originalID)
    }

    // MARK: - openInActiveTab

    func testOpenInActiveTabLoadsIntoSelectedTab() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "# A")
        XCTAssertTrue(controller.openInActiveTab(url: a))
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.selectedEditor.fileURL?.path, a.path)
        XCTAssertEqual(controller.selectedEditor.text, "# A")
        XCTAssertFalse(controller.selectedEditor.isDirty)
    }

    func testOpenInActiveTabSamePathPreservesDirtyBuffer() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "original")
        XCTAssertTrue(controller.openInActiveTab(url: a))
        let editor = controller.selectedEditor
        editor.text = "unsaved edits"
        editor.isDirty = true
        XCTAssertTrue(controller.openInActiveTab(url: a))
        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(editor.text, "unsaved edits")
    }

    func testOpenInActiveTabPreservesBufferWhenDirtySaveFails() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "original")
        XCTAssertTrue(controller.openInActiveTab(url: a))
        let editor = controller.selectedEditor
        editor.text = "unsaved edits"
        editor.isDirty = true
        try FileManager.default.removeItem(at: a)

        let b = try note("b.md")
        XCTAssertFalse(controller.openInActiveTab(url: b))
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertTrue(editor === controller.selectedEditor)
        XCTAssertEqual(editor.fileURL?.path, a.path)
        XCTAssertEqual(editor.text, "unsaved edits")
        XCTAssertTrue(editor.isDirty)
        XCTAssertTrue(editor.hasMissingFile)
    }

    // MARK: - openInNewTab

    func testOpenInNewTabOpensSelectsAndReportsCreatedTab() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "A body")
        var createdTabs: [NoteTab] = []
        XCTAssertTrue(controller.openInNewTab(url: a, onCreated: { createdTabs.append($0) }))
        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertEqual(createdTabs.count, 1)
        XCTAssertTrue(createdTabs[0] === controller.selectedTab)
        XCTAssertEqual(controller.selectedEditor.text, "A body")
        XCTAssertEqual(controller.selectedTab?.title, "a")
    }

    func testOpenInNewTabSelectsAlreadyOpenNote() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "A body")
        XCTAssertTrue(controller.openInNewTab(url: a))
        controller.select(controller.tabs[0].id)
        XCTAssertTrue(controller.openInNewTab(url: a))
        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertEqual(controller.selectedEditor.fileURL?.path, a.path)
    }

    func testOpenInNewTabFailureRollsBackTabAndSelection() throws {
        let controller = NoteTabController()
        let a = try note("a.md")
        XCTAssertTrue(controller.openInNewTab(url: a))
        let emptyTab = controller.tabs[0]
        controller.select(emptyTab.id)
        let idsBefore = controller.tabs.map(\.id)

        var failedEditors: [EditorViewModel] = []
        let missing = tempRoot.appendingPathComponent("missing.md")
        XCTAssertFalse(controller.openInNewTab(url: missing, onFailed: { failedEditors.append($0) }))
        XCTAssertEqual(failedEditors.count, 1)
        XCTAssertEqual(failedEditors[0].lastError?.context, .openNote)
        XCTAssertEqual(controller.tabs.map(\.id), idsBefore)
        XCTAssertEqual(controller.selectedTabID, emptyTab.id)
    }

    // MARK: - close

    func testCloseLastTabLeavesOneEmptyTab() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "A body")
        XCTAssertTrue(controller.openInActiveTab(url: a))
        let onlyID = controller.selectedTabID!
        XCTAssertTrue(controller.close(id: onlyID))
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.selectedTabID, onlyID)
        XCTAssertNil(controller.selectedEditor.fileURL)
        XCTAssertEqual(controller.selectedEditor.text, "")
        XCTAssertEqual(controller.tabs[0].title, "New Tab")
    }

    func testCloseMiddleTabMovesSelectionToNext() throws {
        let controller = NoteTabController()
        let a = try note("a.md")
        let c = try note("c.md")
        XCTAssertTrue(controller.openInNewTab(url: a))
        XCTAssertTrue(controller.openInNewTab(url: c))
        // Tabs: [empty, a, c]; c is selected. Closing a selects the next tab.
        let aTab = controller.tabs[1]
        XCTAssertTrue(controller.close(id: aTab.id))
        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertEqual(controller.selectedEditor.fileURL?.path, c.path)
    }

    func testCloseUnselectedTabKeepsSelection() throws {
        let controller = NoteTabController()
        let a = try note("a.md")
        let c = try note("c.md")
        XCTAssertTrue(controller.openInNewTab(url: a))
        XCTAssertTrue(controller.openInNewTab(url: c))
        let emptyTab = controller.tabs[0]
        controller.select(emptyTab.id)
        let aTab = controller.tabs[1]
        XCTAssertTrue(controller.close(id: aTab.id))
        XCTAssertEqual(controller.selectedTabID, emptyTab.id)
        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertEqual(controller.tabs[1].editor.fileURL?.path, c.path)
    }

    func testCloseBlockedWhenDirtyTabFileVanished() throws {
        let controller = NoteTabController()
        let a = try note("a.md", content: "original")
        XCTAssertTrue(controller.openInActiveTab(url: a))
        let editor = controller.selectedEditor
        editor.text = "unsaved edits"
        editor.isDirty = true
        try FileManager.default.removeItem(at: a)

        XCTAssertFalse(controller.close(id: controller.selectedTabID!))
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(editor.fileURL?.path, a.path)
        XCTAssertTrue(editor.isDirty)
        XCTAssertTrue(editor.hasMissingFile)
    }

    // MARK: - relocateOpenNotes

    func testRelocateOpenNotesRetargetsMatchingPathsOnly() throws {
        let sub = tempRoot.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let a = sub.appendingPathComponent("a.md")
        try "A body".write(to: a, atomically: true, encoding: .utf8)
        let top = try note("top.md", content: "Top body")
        let other = try note("other.md", content: "Other body")

        let controller = NoteTabController()
        XCTAssertTrue(controller.openInNewTab(url: a))
        XCTAssertTrue(controller.openInNewTab(url: top))
        XCTAssertTrue(controller.openInNewTab(url: other))
        let aEditor = controller.tabs[1].editor
        let topEditor = controller.tabs[2].editor
        let otherEditor = controller.tabs[3].editor

        let renamedSub = tempRoot.appendingPathComponent("renamed", isDirectory: true)
        try FileManager.default.moveItem(at: sub, to: renamedSub)
        let renamedTop = tempRoot.appendingPathComponent("renamed-top.md")
        try FileManager.default.moveItem(at: top, to: renamedTop)

        controller.relocateOpenNotes(oldPath: sub.path, newURL: renamedSub)
        controller.relocateOpenNotes(oldPath: top.path, newURL: renamedTop)

        XCTAssertEqual(aEditor.fileURL?.path, renamedSub.appendingPathComponent("a.md").path)
        XCTAssertEqual(aEditor.text, "A body")
        XCTAssertEqual(topEditor.fileURL?.path, renamedTop.path)
        XCTAssertEqual(otherEditor.fileURL?.path, other.path)
    }
}
