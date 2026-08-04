import XCTest
import AppKit
@testable import Lyra

final class MarkdownHighlighterTests: XCTestCase {
    private var boldFont: NSFont { LyraFonts.ui(size: 14, weight: .bold) }
    private var baseFont: NSFont { LyraFonts.ui(size: 14) }

    func testHeadingRuleAppliesBoldFontAndHeadingColor() {
        let storage = NSTextStorage(string: "# Title\nplain")
        MarkdownHighlighter.applyHighlighting(to: storage)

        var range = NSRange(location: 0, length: 0)
        let headingAttrs = storage.attributes(at: 0, effectiveRange: &range)
        let headingFont = headingAttrs[.font] as? NSFont
        XCTAssertEqual(headingFont?.fontName, boldFont.fontName)
        XCTAssertEqual(headingAttrs[.foregroundColor] as? NSColor, LyraTheme.heading)

        let plainIndex = (storage.string as NSString).range(of: "plain").location
        let plainAttrs = storage.attributes(at: plainIndex, effectiveRange: &range)
        let plainFont = plainAttrs[.font] as? NSFont
        XCTAssertEqual(plainFont?.fontName, baseFont.fontName)
    }

    func testCaretAtEndHighlightsLastParagraph() {
        let source = "intro\n# Head"
        let storage = NSTextStorage(string: source)
        MarkdownHighlighter.applyHighlighting(to: storage)
        let end = NSRange(location: storage.length, length: 0)
        MarkdownHighlighter.applyHighlighting(to: storage, range: end)

        let headIndex = (source as NSString).range(of: "# Head").location
        var range = NSRange(location: 0, length: 0)
        let headAttrs = storage.attributes(at: headIndex, effectiveRange: &range)
        XCTAssertEqual(headAttrs[.foregroundColor] as? NSColor, LyraTheme.heading)
        let headFont = headAttrs[.font] as? NSFont
        XCTAssertEqual(headFont?.fontName, boldFont.fontName)

        let introAttrs = storage.attributes(at: 0, effectiveRange: &range)
        XCTAssertNotEqual(introAttrs[.foregroundColor] as? NSColor, LyraTheme.heading)
    }

    func testBoldSpanReceivesBoldFont() {
        let storage = NSTextStorage(string: "hello **world**")
        let before = storage.string
        MarkdownHighlighter.applyHighlighting(to: storage)
        XCTAssertEqual(storage.string, before)
        let boldIndex = (before as NSString).range(of: "**world**").location
        var range = NSRange(location: 0, length: 0)
        let attrs = storage.attributes(at: boldIndex, effectiveRange: &range)
        let font = attrs[.font] as? NSFont
        XCTAssertEqual(font?.fontName, boldFont.fontName)
    }
}
