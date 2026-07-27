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

    func testParseRangedMatchesSubstrings() {
        let source = "# Title\n\nBody text\n\n- item\n"
        let ranged = MarkdownPreviewBlocks.parseRanged(source)
        let ns = source as NSString
        XCTAssertEqual(ranged.count, 3)
        for item in ranged {
            let slice = ns.substring(with: item.range)
            switch item.block {
            case .heading(1, "Title"):
                XCTAssertEqual(slice, "# Title")
            case .paragraph("Body text"):
                XCTAssertEqual(slice, "Body text")
            case .listItem("item"):
                XCTAssertTrue(slice.hasSuffix("item"))
            default:
                XCTFail("Unexpected block \(item.block)")
            }
        }
    }

    func testReplacingBlockRange() {
        let source = "# Title\n\nBody\n"
        let ranged = MarkdownPreviewBlocks.parseRanged(source)
        guard let heading = ranged.first else {
            return XCTFail("expected blocks")
        }
        let next = MarkdownPreviewBlocks.replacing(in: source, range: heading.range, with: "## Renamed")
        XCTAssertTrue(next.hasPrefix("## Renamed"))
        XCTAssertTrue(next.contains("Body"))
        let blocks = MarkdownPreviewBlocks.parse(next)
        XCTAssertEqual(blocks[0], .heading(level: 2, text: "Renamed"))
    }

    func testReplacingMiddleBlockKeepsNeighbors() {
        let source = """
        One

        Two

        Three
        """
        let ranged = MarkdownPreviewBlocks.parseRanged(source)
        XCTAssertEqual(ranged.count, 3)
        let next = MarkdownPreviewBlocks.replacing(in: source, range: ranged[1].range, with: "Dos")
        let blocks = MarkdownPreviewBlocks.parse(next)
        XCTAssertEqual(blocks, [
            .paragraph("One"),
            .paragraph("Dos"),
            .paragraph("Three"),
        ])
    }

    func testCodeFenceRangeIncludesFences() {
        let source = "```\ncode\n```\n"
        let ranged = MarkdownPreviewBlocks.parseRanged(source)
        XCTAssertEqual(ranged.count, 1)
        let slice = (source as NSString).substring(with: ranged[0].range)
        XCTAssertTrue(slice.hasPrefix("```"))
        XCTAssertTrue(slice.contains("code"))
        XCTAssertTrue(slice.hasSuffix("```") || slice.contains("```"))
    }
}
