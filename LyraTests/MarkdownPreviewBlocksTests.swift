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
        XCTAssertEqual(blocks[3], .listItem(text: "one", ordinal: nil, depth: 0, taskChecked: nil))
        XCTAssertEqual(blocks[4], .listItem(text: "two", ordinal: nil, depth: 0, taskChecked: nil))
        XCTAssertEqual(blocks[5], .code("code"))
        XCTAssertEqual(blocks[6], .quote("quote"))
        XCTAssertEqual(blocks[7], .thematicBreak)
        XCTAssertEqual(blocks[8], .paragraph("End [[Wiki]]"))
    }

    func testOrderedListKeepsOrdinals() {
        let blocks = MarkdownPreviewBlocks.parse("1. first\n2. second\n3. third\n")
        XCTAssertEqual(blocks[0], .listItem(text: "first", ordinal: 1, depth: 0, taskChecked: nil))
        XCTAssertEqual(blocks[1], .listItem(text: "second", ordinal: 2, depth: 0, taskChecked: nil))
        XCTAssertEqual(blocks[2], .listItem(text: "third", ordinal: 3, depth: 0, taskChecked: nil))
    }

    func testNestedListDepth() {
        let blocks = MarkdownPreviewBlocks.parse("- outer\n  - inner\n")
        XCTAssertEqual(blocks[0], .listItem(text: "outer", ordinal: nil, depth: 0, taskChecked: nil))
        XCTAssertEqual(blocks[1], .listItem(text: "inner", ordinal: nil, depth: 1, taskChecked: nil))
    }

    func testTaskListItems() {
        let blocks = MarkdownPreviewBlocks.parse("- [x] done\n- [ ] todo\n- [X] also\n- plain\n")
        XCTAssertEqual(blocks[0], .listItem(text: "done", ordinal: nil, depth: 0, taskChecked: true))
        XCTAssertEqual(blocks[1], .listItem(text: "todo", ordinal: nil, depth: 0, taskChecked: false))
        XCTAssertEqual(blocks[2], .listItem(text: "also", ordinal: nil, depth: 0, taskChecked: true))
        XCTAssertEqual(blocks[3], .listItem(text: "plain", ordinal: nil, depth: 0, taskChecked: nil))
    }

    func testPrepareInlineTurnsWikiIntoLinks() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("See [[Home Page]] and *more*")
        XCTAssertTrue(prepared.contains("[Home Page](lyra-wiki:Home%20Page)"), "got: \(prepared)")
        XCTAssertFalse(prepared.contains("[[Home Page]]"))
        XCTAssertTrue(prepared.contains("*more*"))
        let url = URL(string: "lyra-wiki:Home%20Page")!
        XCTAssertEqual(MarkdownPreviewBlocks.wikiLinkName(from: url), "Home Page")
    }

    func testParseImageBlock() {
        let blocks = MarkdownPreviewBlocks.parse("![a](_attachments/b.png)\n")
        XCTAssertEqual(blocks, [.image(alt: "a", path: "_attachments/b.png")])
    }

    func testParseImageBlockAmongOtherBlocks() {
        let source = """
        # Title

        ![shot](_attachments/x.png)

        After
        """
        let blocks = MarkdownPreviewBlocks.parse(source)
        XCTAssertEqual(blocks[0], .heading(level: 1, text: "Title"))
        XCTAssertEqual(blocks[1], .image(alt: "shot", path: "_attachments/x.png"))
        XCTAssertEqual(blocks[2], .paragraph("After"))
    }

    func testInlineImageInParagraphStaysParagraph() {
        let blocks = MarkdownPreviewBlocks.parse("Hello ![a](b.png) world\n")
        XCTAssertEqual(blocks, [.paragraph("Hello ![a](b.png) world")])
    }
}
