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
    }

    func testApplyingTitleSanitizesRenameStem() {
        let md = "body"
        let result = NoteTitle.applyingTitle("  Bad/Name  ", to: md)
        XCTAssertEqual(result.renamedStem, "Untitled")
        XCTAssertEqual(result.markdown, md)
    }

    func testApplyingTitleStripsMdSuffixForRename() {
        let md = "body"
        let result = NoteTitle.applyingTitle("Note.md", to: md)
        XCTAssertEqual(result.renamedStem, "Note")
        XCTAssertEqual(result.markdown, md)
    }
}
