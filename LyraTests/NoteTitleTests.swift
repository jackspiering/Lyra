import XCTest
@testable import Lyra

final class NoteTitleTests: XCTestCase {
    // MARK: - displayTitle

    func testDisplayTitleUsesLeadingH1() {
        let md = "# Hello World\n\nBody paragraph."
        let url = URL(fileURLWithPath: "/vault/Welcome.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: md, fileURL: url), "Hello World")
    }

    func testDisplayTitleSkipsBlankLinesBeforeH1() {
        let md = "\n\n  \n# Real Title\nmore"
        let url = URL(fileURLWithPath: "/vault/file.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: md, fileURL: url), "Real Title")
    }

    func testDisplayTitleFallsBackToFilenameStemWhenNoH1() {
        let md = "Just a paragraph.\n\n## Not H1"
        let url = URL(fileURLWithPath: "/vault/Welcome.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: md, fileURL: url), "Welcome")
    }

    func testDisplayTitleFallsBackWhenH2IsFirst() {
        let md = "## Section\n\n# Later H1 ignored for leading rule"
        let url = URL(fileURLWithPath: "/vault/Note.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: md, fileURL: url), "Note")
    }

    func testDisplayTitleIgnoresHashWithoutSpace() {
        let md = "#NotAHeading\n"
        let url = URL(fileURLWithPath: "/vault/Stem.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: md, fileURL: url), "Stem")
    }

    func testDisplayTitleEmptyMarkdownUsesStem() {
        let url = URL(fileURLWithPath: "/vault/Empty.md")
        XCTAssertEqual(NoteTitle.displayTitle(markdown: "", fileURL: url), "Empty")
    }

    func testDisplayTitleNilURLWithoutH1IsEmpty() {
        XCTAssertEqual(NoteTitle.displayTitle(markdown: "no h1", fileURL: nil), "")
    }

    func testDisplayTitleNilURLWithH1UsesH1() {
        XCTAssertEqual(NoteTitle.displayTitle(markdown: "# Solo\n", fileURL: nil), "Solo")
    }

    // MARK: - applyingTitle (H1 path)

    func testApplyingTitleReplacesLeadingH1() {
        let md = "# Old\n\nBody stays."
        let result = NoteTitle.applyingTitle("New Title", to: md)
        XCTAssertEqual(result.markdown, "# New Title\n\nBody stays.")
        XCTAssertNil(result.renamedStem)
    }

    func testApplyingTitlePreservesBlankLinesAndBody() {
        let md = "\n# Alpha\nline2\n"
        let result = NoteTitle.applyingTitle("Beta", to: md)
        XCTAssertEqual(result.markdown, "\n# Beta\nline2\n")
        XCTAssertNil(result.renamedStem)
    }

    func testApplyingTitleDoesNotRenameWhenH1Exists() {
        let md = "# Keep Path\n"
        let result = NoteTitle.applyingTitle("Still H1", to: md)
        XCTAssertNil(result.renamedStem)
        XCTAssertTrue(result.markdown.hasPrefix("# Still H1"))
    }

    func testApplyingTitleSameH1IsNoOp() {
        let md = "# Same\nbody"
        let result = NoteTitle.applyingTitle("Same", to: md)
        XCTAssertEqual(result.markdown, md)
        XCTAssertNil(result.renamedStem)
    }

    // MARK: - applyingTitle (rename path)

    func testApplyingTitleWithoutH1RequestsRename() {
        let md = "No heading here.\n"
        let result = NoteTitle.applyingTitle("My Note", to: md)
        XCTAssertEqual(result.markdown, md)
        XCTAssertEqual(result.renamedStem, "My Note")
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
    }

    func testApplyingTitleIgnoresLaterH1ForRenameDecision() {
        // First non-empty is a paragraph, so later H1 does not count.
        let md = "intro\n\n# Later\n"
        let result = NoteTitle.applyingTitle("Renamed", to: md)
        XCTAssertEqual(result.renamedStem, "Renamed")
        XCTAssertEqual(result.markdown, md)
    }
}
