import XCTest
@testable import Lyra

final class NoteStatsTests: XCTestCase {
    func testWordCountSimple() {
        XCTAssertEqual(NoteStats.wordCount("hello world"), 2)
        XCTAssertEqual(NoteStats.wordCount("  a   b\nc  "), 2)
    }

    func testWordCountEmpty() {
        XCTAssertEqual(NoteStats.wordCount(""), 0)
        XCTAssertEqual(NoteStats.wordCount("   \n\t  "), 0)
    }

    func testWordCountSingle() {
        XCTAssertEqual(NoteStats.wordCount("one"), 1)
    }

    func testLetterCountIgnoresSpacesAndPunctuation() {
        XCTAssertEqual(NoteStats.letterCount("Hi!"), 2)
    }

    func testLetterCountUnicode() {
        XCTAssertEqual(NoteStats.letterCount("café"), 4)
        XCTAssertEqual(NoteStats.letterCount("Hello, 世界!"), 7)
    }

    func testLetterCountEmpty() {
        XCTAssertEqual(NoteStats.letterCount(""), 0)
        XCTAssertEqual(NoteStats.letterCount(" 123 !"), 0)
    }
}
