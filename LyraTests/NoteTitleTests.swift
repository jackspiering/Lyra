import XCTest
@testable import Lyra

final class NoteTitleTests: XCTestCase {
    func testDisplayTitleUsesFilenameStem() {
        let url = URL(fileURLWithPath: "/vault/Welcome.md")
        XCTAssertEqual(NoteTitle.displayTitle(fileURL: url), "Welcome")
    }

    func testDisplayTitleKeepsInnerDots() {
        let url = URL(fileURLWithPath: "/vault/Node.js.md")
        XCTAssertEqual(NoteTitle.displayTitle(fileURL: url), "Node.js")
    }

    func testDisplayTitleNilURLIsEmpty() {
        XCTAssertEqual(NoteTitle.displayTitle(fileURL: nil), "")
    }

    func testApplyingTitleAlwaysRequestsRenameAndLeavesMarkdown() {
        let md = "# Old\n\nBody stays."
        let result = NoteTitle.applyingTitle("New Title", to: md)
        XCTAssertEqual(result.markdown, md)
        XCTAssertEqual(result.renamedStem, "New Title")
        XCTAssertNil(result.error)
    }

    func testApplyingTitleRejectsInvalidStem() {
        let md = "body"
        let result = NoteTitle.applyingTitle("  Bad/Name  ", to: md)
        XCTAssertNil(result.renamedStem)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.markdown, md)
    }

    func testApplyingTitleStripsMdSuffixForRename() {
        let md = "body"
        let result = NoteTitle.applyingTitle("Note.md", to: md)
        XCTAssertEqual(result.renamedStem, "Note")
        XCTAssertEqual(result.markdown, md)
    }

    func testBreadcrumbListsVaultThenFolders() {
        let root = URL(fileURLWithPath: "/Users/me/Field Notes")
        let note = URL(fileURLWithPath: "/Users/me/Field Notes/Essays/Drafts/On Slow Writing.md")
        XCTAssertEqual(
            NoteTitle.breadcrumb(fileURL: note, vaultRoot: root),
            ["Field Notes", "Essays", "Drafts"]
        )
    }

    func testBreadcrumbAtVaultRootIsVaultName() {
        let root = URL(fileURLWithPath: "/vault")
        let note = URL(fileURLWithPath: "/vault/Inbox.md")
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: note, vaultRoot: root), ["vault"])
    }

    func testBreadcrumbOutsideVaultOrMissingIsEmpty() {
        let root = URL(fileURLWithPath: "/vault")
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: URL(fileURLWithPath: "/elsewhere/A.md"), vaultRoot: root), [])
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: URL(fileURLWithPath: "/vault-2/A.md"), vaultRoot: root), [])
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: nil, vaultRoot: root), [])
    }
}
