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
        aliases: [URL: [String]] = [:]
    ) -> WikiLinkResolver {
        WikiLinkResolver(noteURLs: urls, vaultRoot: root, aliases: aliases)
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
        let resolver = makeResolver(urls: [hello, world])
        let urlBodies = [
            world: "See [[Hello]] and a [file](Hello.md)",
            hello: "self [[Hello]] ignored",
        ]
        let links = resolver.backlinks(to: hello, bodies: urlBodies)
        XCTAssertEqual(links.map(\.url), [world])
    }

    func testBacklinksIgnoreAmbiguousMentions() {
        let resolver = makeResolver(urls: [dupA, dupB, hello])
        let bodies = [
            hello: "See [[Dup]]",
        ]
        XCTAssertTrue(resolver.backlinks(to: dupA, bodies: bodies).isEmpty)
        XCTAssertTrue(resolver.backlinks(to: dupB, bodies: bodies).isEmpty)
    }
}
