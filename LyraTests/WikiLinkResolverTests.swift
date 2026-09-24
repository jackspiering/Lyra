import XCTest
@testable import Lyra

final class WikiLinkResolverTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/vault")
    private let hello = URL(fileURLWithPath: "/vault/Hello.md")
    private let world = URL(fileURLWithPath: "/vault/sub/World.md")
    private let dupA = URL(fileURLWithPath: "/vault/Dup.md")
    private let dupB = URL(fileURLWithPath: "/vault/other/Dup.md")
    private let aliased = URL(fileURLWithPath: "/vault/Projects/Roadmap.md")

    private func makeResolver(
        urls: [URL],
        aliases: [URL: [String]] = [:],
        bodies: [URL: String] = [:]
    ) -> WikiLinkResolver {
        WikiLinkResolver(noteURLs: urls, vaultRoot: root, aliases: aliases, bodies: bodies)
    }

    func testResolvesPlainName() {
        let result = makeResolver(urls: [hello, world]).resolve("Hello")
        XCTAssertEqual(result, .unique(hello))
    }

    func testResolvesNameWithMdSuffix() {
        XCTAssertEqual(makeResolver(urls: [hello]).resolve("Hello.md"), .unique(hello))
    }

    func testCaseInsensitive() {
        let resolver = makeResolver(urls: [hello])
        XCTAssertEqual(resolver.resolve("hello"), .unique(hello))
        XCTAssertEqual(resolver.resolve("HELLO"), .unique(hello))
    }

    func testMissingReturnsUnresolved() {
        XCTAssertEqual(makeResolver(urls: [hello]).resolve("Missing"), .unresolved)
    }

    func testDuplicateStemsAreAmbiguous() {
        switch makeResolver(urls: [dupA, dupB]).resolve("Dup") {
        case .ambiguous(let candidates):
            XCTAssertEqual(Set(candidates.map(\.url)), Set([dupA, dupB]))
        default:
            XCTFail("expected ambiguous")
        }
    }

    func testPathDisambiguatesDuplicateStems() {
        let resolver = makeResolver(urls: [dupA, dupB])
        XCTAssertEqual(resolver.resolve("other/Dup"), .unique(dupB))
        if case .ambiguous(let candidates) = resolver.resolve("Dup") {
            XCTAssertEqual(Set(candidates.map(\.url)), Set([dupA, dupB]))
        } else {
            XCTFail("bare Dup should stay ambiguous")
        }
    }

    func testExactPathMatch() {
        XCTAssertEqual(makeResolver(urls: [world]).resolve("sub/World"), .unique(world))
    }

    func testPathSuffixMatch() {
        XCTAssertEqual(makeResolver(urls: [world]).resolve("sub/World.md"), .unique(world))
    }

    func testWrongFolderPathIsUnresolved() {
        XCTAssertEqual(makeResolver(urls: [world]).resolve("Daily Notes/World"), .unresolved)
    }

    func testTrimsWhitespaceAndAliasDisplay() {
        let resolver = makeResolver(urls: [hello])
        XCTAssertEqual(resolver.resolve("  Hello  "), .unique(hello))
        XCTAssertEqual(resolver.resolve("Hello|hi"), .unique(hello))
    }

    func testRealStemBeatsAlias() {
        let resolver = makeResolver(
            urls: [hello, aliased],
            aliases: [aliased: ["Hello"]]
        )
        XCTAssertEqual(resolver.resolve("Hello"), .unique(hello))
    }

    func testAliasUsedWhenNoStemMatches() {
        let resolver = makeResolver(urls: [aliased], aliases: [aliased: ["Plan"]])
        XCTAssertEqual(resolver.resolve("Plan"), .unique(aliased))
    }

    func testTwoAliasesAreAmbiguous() {
        let other = URL(fileURLWithPath: "/vault/Other.md")
        switch makeResolver(
            urls: [aliased, other],
            aliases: [aliased: ["Plan"], other: ["Plan"]]
        ).resolve("Plan") {
        case .ambiguous(let candidates):
            XCTAssertEqual(candidates.count, 2)
        default:
            XCTFail("expected ambiguous aliases")
        }
    }

    func testBacklinksCountUniqueWikiOnly() {
        let urlBodies = [
            world: "See [[Hello]] and a [file](Hello.md)",
            hello: "self [[Hello]] ignored",
        ]
        let resolver = makeResolver(urls: [hello, world], bodies: urlBodies)
        let links = resolver.backlinks(to: hello)
        XCTAssertEqual(links.map(\.url), [world])
    }

    func testBacklinksIgnoreAmbiguousMentions() {
        let bodies = [
            hello: "See [[Dup]]",
        ]
        let resolver = makeResolver(urls: [dupA, dupB, hello], bodies: bodies)
        XCTAssertTrue(resolver.backlinks(to: dupA).isEmpty)
        XCTAssertTrue(resolver.backlinks(to: dupB).isEmpty)
    }

    func testBacklinksLiveOverlayRecomputesOpenNote() {
        let indexed = [
            world: "See [[Hello]]",
            hello: "",
        ]
        let resolver = makeResolver(urls: [hello, world], bodies: indexed)
        XCTAssertEqual(resolver.backlinks(to: hello).map(\.url), [world])

        let afterEdit = resolver.backlinks(to: hello, liveBodies: [world: "no links"])
        XCTAssertTrue(afterEdit.isEmpty)

        let added = resolver.backlinks(to: world, liveBodies: [hello: "now [[World]]"])
        XCTAssertEqual(added.map(\.url), [hello])
    }

    // MARK: - Backlink context

    func testBacklinkContextShowsSurroundingLineWithDisplayText() {
        let resolver = makeResolver(urls: [hello, world])
        let body = "# World\n\nI keep coming back to [[Hello|the greeting]] every morning.\nNext line."
        let context = resolver.backlinkContext(in: body, to: hello)
        XCTAssertEqual(
            context,
            BacklinkContext(before: "I keep coming back to ", link: "the greeting", after: " every morning.")
        )
    }

    func testBacklinkContextSkipsLinksToOtherNotesAndCodeSpans() {
        let resolver = makeResolver(urls: [hello, world])
        let body = "`[[Hello]]` then [[World]] then - [[Hello]]"
        let context = resolver.backlinkContext(in: body, to: hello)
        XCTAssertEqual(context?.link, "Hello")
        XCTAssertEqual(context?.before, "`[[Hello]]` then [[World]] then - ")
        XCTAssertEqual(context?.after, "")
    }

    func testBacklinkContextDropsLeadingListMarkerAndClipsLongLines() {
        let resolver = makeResolver(urls: [hello])
        let listed = resolver.backlinkContext(in: "- [[Hello]]\n", to: hello)
        XCTAssertEqual(listed, BacklinkContext(before: "", link: "Hello", after: ""))

        let long = String(repeating: "a", count: 100) + " [[Hello]] " + String(repeating: "b", count: 100)
        let clipped = resolver.backlinkContext(in: long, to: hello, radius: 10)
        XCTAssertEqual(clipped?.before.first, "…")
        XCTAssertEqual(clipped?.after.last, "…")
        XCTAssertEqual(clipped?.link, "Hello")
    }

    func testBacklinkContextNilWhenNoLinkResolvesToTarget() {
        let resolver = makeResolver(urls: [hello, world])
        XCTAssertNil(resolver.backlinkContext(in: "only [[World]] here", to: hello))
    }
}
