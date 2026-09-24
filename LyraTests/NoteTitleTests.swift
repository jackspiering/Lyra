import XCTest
@testable import Lyra

final class NoteTitleTests: XCTestCase {
    func testDisplayTitleUsesFilenameStemEvenWhenH1Exists() {
        let md = "# Hello World\n\nBody paragraph."
        let url = URL(fileURLWithPath: "/vault/Welcome.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: md, fileURL: url), "Welcome")
    }

    func testDisplayTitleEmptyMarkdownUsesStem() {
        let url = URL(fileURLWithPath: "/vault/Empty.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: "", fileURL: url), "Empty")
    }

    func testDisplayTitleNilURLIsEmpty() {
        XCTAssertEqual(NoteTitle.displayTitle(markdown: "# Solo\n", fileURL: nil), "")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: "no h1", fileURL: nil), "")
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
