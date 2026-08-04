import XCTest
@testable import Lyra

final class NoteStatsTests: XCTestCase {
    func testWordCountSimple() {
        XCTAssertEqual(NoteStats.wordCount("hello world"), 2)
        // a, b, c — three whitespace-separated tokens (including newline)
        XCTAssertEqual(NoteStats.wordCount("  a   b\nc  "), 3)
    }

    func testWordCountEmpty() {
        XCTAssertEqual(NoteStats.wordCount(""), 0)
        XCTAssertEqual(NoteStats.wordCount("   \n\t  "), 0)
    }

    func testWordCountSingle() {
        XCTAssertEqual(NoteStats.wordCount("one"), 1)
    }

    func testCharacterCountIncludesSpacesAndPunctuation() {
        XCTAssertEqual(NoteStats.characterCount("Hi!"), 3)
        XCTAssertEqual(NoteStats.characterCount("a b"), 3)
    }

    func testCharacterCountEmpty() {
        XCTAssertEqual(NoteStats.characterCount(""), 0)
    }

    func testCharacterCountUnicodeGraphemeClusters() {
        // café: c, a, f, é (precomposed) → 4 clusters
        XCTAssertEqual(NoteStats.characterCount("café"), 4)
        // Family emoji is one extended grapheme cluster when presented as a single character sequence
        XCTAssertEqual(NoteStats.characterCount("a👍b"), 3)
    }
}
