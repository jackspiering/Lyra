import XCTest
@testable import Lyra

final class VaultFullTextSearchTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/vault/Welcome.md")
    private let b = URL(fileURLWithPath: "/vault/Projects/Roadmap.md")

    func testEmptyQueryReturnsNothing() {
        let docs = [
            VaultFullTextSearch.Document(url: a, relativePath: "Welcome.md", body: "hello"),
        ]
        XCTAssertTrue(VaultFullTextSearch.search(documents: docs, query: "  ").isEmpty)
    }

    func testBodyMatchIncludesSnippet() {
        let docs = [
            VaultFullTextSearch.Document(
                url: a,
                relativePath: "Welcome.md",
                body: "A long note that mentions oranges in the middle of the sentence."
            ),
        ]
        let hits = VaultFullTextSearch.search(documents: docs, query: "oranges")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].url, a)
        XCTAssertTrue(hits[0].snippet.localizedCaseInsensitiveContains("oranges"))
    }

    func testPathMatchWithoutBodyHit() {
        let docs = [
            VaultFullTextSearch.Document(url: b, relativePath: "Projects/Roadmap.md", body: "nothing"),
        ]
        let hits = VaultFullTextSearch.search(documents: docs, query: "Roadmap")
        XCTAssertEqual(hits.map(\.url), [b])
        XCTAssertEqual(hits[0].snippet, "Projects/Roadmap.md")
    }

    func testCaseInsensitiveAndSorted() {
        let docs = [
            VaultFullTextSearch.Document(url: b, relativePath: "Projects/Roadmap.md", body: "Zebra"),
            VaultFullTextSearch.Document(url: a, relativePath: "Welcome.md", body: "zebra"),
        ]
        let hits = VaultFullTextSearch.search(documents: docs, query: "ZEBRA")
        XCTAssertEqual(hits.map(\.relativePath), ["Projects/Roadmap.md", "Welcome.md"])
    }
}
