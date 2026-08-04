import XCTest
import AppKit
@testable import Lyra

final class MarkdownHighlighterTests: XCTestCase {
    func testAttributedStringAppliesHeadingStyle() {
        let result = MarkdownHighlighter.attributedString(from: "# Title\nplain")
        XCTAssertEqual(result.string, "# Title\nplain")
        var range = NSRange(location: 0, length: 0)
        let attrs = result.attributes(at: 0, effectiveRange: &range)
        XCTAssertNotNil(attrs[.foregroundColor])
        // Heading rule covers the first line.
        XCTAssertGreaterThan(range.length, 0)
    }

    func testInPlaceHighlightDoesNotChangeCharacters() {
        let storage = NSTextStorage(string: "hello **world**")
        let before = storage.string
        MarkdownHighlighter.applyHighlighting(to: storage)
        XCTAssertEqual(storage.string, before)
        XCTAssertEqual(storage.length, (before as NSString).length)
    }

    func testParagraphScopedRestyleLeavesOtherParagraphsUntouchedInLength() {
        let storage = NSTextStorage(string: "line one\n## Head\nline three")
        MarkdownHighlighter.applyHighlighting(to: storage)
        let fullLength = storage.length
        // Restyle only the middle paragraph region.
        let mid = NSRange(location: 9, length: 1)
        MarkdownHighlighter.applyHighlighting(to: storage, range: mid)
        XCTAssertEqual(storage.length, fullLength)
        XCTAssertEqual(storage.string, "line one\n## Head\nline three")
    }
}
