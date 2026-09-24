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

    func testPrepareInlineSkipsWikiInsideCodeSpans() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown(
            "Tip: click any `[[wiki link]]` now"
        )
        XCTAssertTrue(prepared.contains("`[[wiki link]]`"), "got: \(prepared)")
        XCTAssertFalse(prepared.contains("lyra-wiki:"), "must not rewrite inside code: \(prepared)")
    }

    func testPrepareInlineStillRewritesBareWiki() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("See [[Home]] please")
        XCTAssertTrue(prepared.contains("[Home](lyra-wiki:Home)"), "got: \(prepared)")
    }

    func testPrepareInlineWikiAlias() {
        // Obsidian [[path|display]]
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("Go [[Daily Notes/2026-07-27|today]]")
        XCTAssertTrue(prepared.contains("[today](lyra-wiki:Daily%20Notes/2026-07-27)"), "got: \(prepared)")
    }

    func testPrepareInlineWikiAliasTrimsWhitespace() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("See [[Hello | hi]]")
        XCTAssertTrue(prepared.contains("[hi](lyra-wiki:Hello)"), "got: \(prepared)")
    }

    func testPrepareInlineEscapesWikiDestinationParentheses() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("See [[A)B]]")
        XCTAssertTrue(prepared.contains("[A)B](lyra-wiki:A%29B)"), "got: \(prepared)")
        XCTAssertEqual(
            MarkdownPreviewBlocks.wikiLinkName(from: URL(string: "lyra-wiki:A%29B")!),
            "A)B"
        )
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

    func testLongFenceDoesNotCloseOnShorterFence() {
        let source = "````swift\ninside\n```\nstill code\n````\nAfter"
        XCTAssertEqual(
            MarkdownPreviewBlocks.parse(source),
            [.code("inside\n```\nstill code"), .paragraph("After")]
        )
    }

    func testTildeFenceUsesMatchingMarkerAndLength() {
        let source = "~~~~\ncode\n~~~\nmore\n~~~~\n"
        XCTAssertEqual(MarkdownPreviewBlocks.parse(source), [.code("code\n~~~\nmore")])
    }

    func testPrepareInlineSkipsWikiInsideDoubleBacktickSpan() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown(
            "Keep ``[[inside]]`` but rewrite [[outside]]"
        )
        XCTAssertTrue(prepared.contains("``[[inside]]``"), "got: \(prepared)")
        XCTAssertTrue(prepared.contains("[outside](lyra-wiki:outside)"), "got: \(prepared)")
    }

    func testImageBlockAcceptsParenthesesAndTitleInDestination() {
        let blocks = MarkdownPreviewBlocks.parse("![shot](images/photo(1).png \"preview\")\n")
        XCTAssertEqual(blocks, [.image(alt: "shot", path: "images/photo(1).png")])
    }

    func testSetextHeadings() {
        XCTAssertEqual(
            MarkdownPreviewBlocks.parse("Title\n===\n"),
            [.heading(level: 1, text: "Title")]
        )
        XCTAssertEqual(
            MarkdownPreviewBlocks.parse("Title\n---\n"),
            [.heading(level: 2, text: "Title")]
        )
    }

    func testThematicBreakVariants() {
        XCTAssertEqual(
            MarkdownPreviewBlocks.parse("Before\n\n- - -\n"),
            [.paragraph("Before"), .thematicBreak]
        )
        XCTAssertEqual(
            MarkdownPreviewBlocks.parse("Before\n\n* * *\n"),
            [.paragraph("Before"), .thematicBreak]
        )
    }

    func testOrderedParenthesisAndListContinuation() {
        XCTAssertEqual(
            MarkdownPreviewBlocks.parse("1) first\n   continued\n"),
            [.listItem(text: "first\ncontinued", ordinal: 1, depth: 0, taskChecked: nil)]
        )
    }

    func testPrepareInlineSkipsEmbedsAndFragments() {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown("Embed ![[Note]] plus [[Note#heading]]")
        XCTAssertTrue(prepared.contains("![[Note]]"), "got: \(prepared)")
        XCTAssertTrue(prepared.contains("[[Note#heading]]"), "got: \(prepared)")
        XCTAssertFalse(prepared.contains("lyra-wiki:"))
    }
    func testLeadingFrontmatterRendersAsCode() {
        let blocks = MarkdownPreviewBlocks.parse("---\naliases: [A]\ntags:\n  - x\n---\n# Title\n")
        XCTAssertEqual(blocks, [.code("aliases: [A]\ntags:\n  - x"), .heading(level: 1, text: "Title")])
    }

    func testUnclosedLeadingRuleIsStillThematicBreak() {
        let blocks = MarkdownPreviewBlocks.parse("---\nBody\n")
        XCTAssertEqual(blocks, [.thematicBreak, .paragraph("Body")])
    }

    func testLinkTargetAllowsOnlyWebAndMail() {
        let web = URL(string: "https://example.com")!
        XCTAssertEqual(MarkdownPreviewBlocks.linkTarget(for: web, noteDirectory: nil, vaultRoot: nil), .external(web))
        let mail = URL(string: "mailto:a@example.com")!
        XCTAssertEqual(MarkdownPreviewBlocks.linkTarget(for: mail, noteDirectory: nil, vaultRoot: nil), .external(mail))
        for raw in ["file:///Applications/Calculator.app", "shortcuts://run-shortcut?name=x", "x-apple.systempreferences:"] {
            XCTAssertEqual(
                MarkdownPreviewBlocks.linkTarget(for: URL(string: raw)!, noteDirectory: nil, vaultRoot: nil),
                .unsupported,
                raw
            )
        }
        XCTAssertEqual(
            MarkdownPreviewBlocks.linkTarget(for: URL(string: "lyra-wiki:My%20Note")!, noteDirectory: nil, vaultRoot: nil),
            .wiki("My Note")
        )
    }

    func testLinkTargetResolvesRelativeNoteInsideVault() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("link-target-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let plan = projects.appendingPathComponent("Plan.md")
        try "plan".write(to: plan, atomically: true, encoding: .utf8)

        let target = MarkdownPreviewBlocks.linkTarget(
            for: URL(string: "Projects/Plan.md#goals")!,
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertEqual(target, .note(plan.standardizedFileURL))
        XCTAssertEqual(
            MarkdownPreviewBlocks.linkTarget(for: URL(string: "../outside.md")!, noteDirectory: root, vaultRoot: root),
            .unsupported
        )
        XCTAssertEqual(
            MarkdownPreviewBlocks.linkTarget(for: URL(string: "Projects/image.png")!, noteDirectory: root, vaultRoot: root),
            .unsupported
        )
    }
}
