import XCTest
@testable import Lyra

final class WikiLinkResolverTests: XCTestCase {
    private let hello = URL(fileURLWithPath: "/vault/Hello.md")
    private let world = URL(fileURLWithPath: "/vault/sub/World.md")
    private let dupA = URL(fileURLWithPath: "/vault/Dup.md")
    private let dupB = URL(fileURLWithPath: "/vault/other/Dup.md")

    func testResolvesPlainName() {
        let resolver = WikiLinkResolver(noteURLs: [hello, world])
        XCTAssertEqual(resolver.resolve("Hello"), hello)
    }

    func testResolvesNameWithMdSuffix() {
        let resolver = WikiLinkResolver(noteURLs: [hello])
        XCTAssertEqual(resolver.resolve("Hello.md"), hello)
    }

    func testCaseInsensitive() {
        let resolver = WikiLinkResolver(noteURLs: [hello])
        XCTAssertEqual(resolver.resolve("hello"), hello)
        XCTAssertEqual(resolver.resolve("HELLO"), hello)
    }

    func testMissingReturnsNil() {
        let resolver = WikiLinkResolver(noteURLs: [hello])
        XCTAssertNil(resolver.resolve("Missing"))
    }

    func testFirstMatchWinsForDuplicateStems() {
        let resolver = WikiLinkResolver(noteURLs: [dupA, dupB])
        XCTAssertEqual(resolver.resolve("Dup"), dupA)
    }

    func testTrimsWhitespace() {
        let resolver = WikiLinkResolver(noteURLs: [hello])
        XCTAssertEqual(resolver.resolve("  Hello  "), hello)
    }
}
