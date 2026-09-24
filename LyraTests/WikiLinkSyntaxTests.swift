import XCTest
@testable import Lyra

final class WikiLinkSyntaxTests: XCTestCase {
    func testParseInnerStripsAliasAndMd() {
        let parsed = WikiLinkSyntax.parseInner("Folder/Note.md | Today")
        XCTAssertEqual(parsed.target, "Folder/Note")
        XCTAssertEqual(parsed.display, "Today")
    }

    func testNormalizeTarget() {
        XCTAssertEqual(WikiLinkSyntax.normalizeTarget("\\Projects\\Roadmap.md"), "Projects/Roadmap")
        XCTAssertEqual(WikiLinkSyntax.normalizeTarget("/Hello/"), "Hello")
    }

    func testExtractSkipsFencedAndInlineCode() {
        let md = """
        See [[Outside]]
        ```
        [[InsideFence]]
        ```
        And `[[inline]]` plus [[Also]]
        """
        let targets = WikiLinkSyntax.extractLinks(in: md).map(\.target)
        XCTAssertEqual(targets, ["Outside", "Also"])
    }

    func testLinkAtOffset() {
        let md = "Go [[Hello]] now"
        let ns = md as NSString
        let start = ns.range(of: "[[").location
        XCTAssertEqual(WikiLinkSyntax.link(atUTF16Offset: start + 2, in: md)?.target, "Hello")
        XCTAssertNil(WikiLinkSyntax.link(atUTF16Offset: 0, in: md))
    }

    func testDestinationBareNameUsesLinkingFolder() {
        let root = URL(fileURLWithPath: "/vault")
        let current = URL(fileURLWithPath: "/vault/Projects/Now.md")
        let dest = WikiLinkSyntax.destinationURL(
            target: "Roadmap",
            vaultRoot: root,
            linkingNoteURL: current
        )
        XCTAssertEqual(dest?.path, "/vault/Projects/Roadmap.md")
    }

    func testDestinationPathUsesVaultRoot() {
        let root = URL(fileURLWithPath: "/vault")
        let current = URL(fileURLWithPath: "/vault/Projects/Now.md")
        let dest = WikiLinkSyntax.destinationURL(
            target: "Inbox/Idea",
            vaultRoot: root,
            linkingNoteURL: current
        )
        XCTAssertEqual(dest?.path, "/vault/Inbox/Idea.md")
    }

    func testDestinationRejectsDotDot() {
        let root = URL(fileURLWithPath: "/vault")
        XCTAssertNil(
            WikiLinkSyntax.destinationURL(
                target: "../Secret",
                vaultRoot: root,
                linkingNoteURL: URL(fileURLWithPath: "/vault/A.md")
            )
        )
    }

    func testExtractSkipsEmbedsAndHeadingFragments() {
        let targets = WikiLinkSyntax.extractLinks(
            in: "Embed ![[Note]] and fragment [[Note#heading]] plus [[Real]]"
        ).map(\.target)
        XCTAssertEqual(targets, ["Real"])
    }
}
