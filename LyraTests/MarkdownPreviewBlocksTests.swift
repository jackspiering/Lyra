import XCTest
@testable import Lyra

final class MarkdownPreviewBlocksTests: XCTestCase {
    func testHeadingsListsAndCode() {
        let source = """
        # Title
        Intro **bold**

        ## Section
        - one
        - two

        ```
        code
        ```

        > quote
        ---
        End [[Wiki]]
        """
        let blocks = MarkdownPreviewBlocks.parse(source)
        XCTAssertEqual(blocks[0], .heading(level: 1, text: "Title"))
        XCTAssertEqual(blocks[1], .paragraph("Intro **bold**"))
        XCTAssertEqual(blocks[2], .heading(level: 2, text: "Section"))
        XCTAssertEqual(blocks[3], .listItem("one"))
        XCTAssertEqual(blocks[4], .listItem("two"))
        XCTAssertEqual(blocks[5], .code("code"))
        XCTAssertEqual(blocks[6], .quote("quote"))
        XCTAssertEqual(blocks[7], .thematicBreak)
        XCTAssertEqual(blocks[8], .paragraph("End [[Wiki]]"))
    }

    func testPrepareInlineProtectsWikiLinks() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("See [[Home Page]] and *more*")
        XCTAssertTrue(prepared.contains("**⟦Home Page⟧**"))
        XCTAssertFalse(prepared.contains("[[Home Page]]"))
        XCTAssertTrue(prepared.contains("*more*"))
    }
}
