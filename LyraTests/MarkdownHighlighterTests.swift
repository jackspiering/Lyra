import XCTest
import AppKit
@testable import Lyra

final class MarkdownHighlighterTests: XCTestCase {
    private var boldFont: NSFont { LyraFonts.ui(size: 14, weight: .bold) }
    private var baseFont: NSFont { LyraFonts.ui(size: 14) }

    override func setUp() {
        super.setUp()
        // Unit tests may not run through LyraApp.init.
        LyraFonts.registerBundledFonts()
    }

    func testHeadingRuleAppliesBoldFontAndHeadingColor() {
        let storage = NSTextStorage(string: "# Title\nplain")
        MarkdownHighlighter.applyHighlighting(to: storage)

        var range = NSRange(location: 0, length: 0)
        let headingAttrs = storage.attributes(at: 0, effectiveRange: &range)
        let headingFont = headingAttrs[.font] as? NSFont
        XCTAssertEqual(headingFont?.fontName, boldFont.fontName)
        assertColor(headingAttrs[.foregroundColor], matches: LyraTheme.heading)

        let plainIndex = (storage.string as NSString).range(of: "plain").location
        let plainAttrs = storage.attributes(at: plainIndex, effectiveRange: &range)
        let plainFont = plainAttrs[.font] as? NSFont
        XCTAssertEqual(plainFont?.fontName, baseFont.fontName)
        // Plain body uses the base text colour, not the heading token.
        assertColor(plainAttrs[.foregroundColor], matches: NSColor.textColor)
    }

    func testCaretAtEndHighlightsLastParagraph() {
        let source = "intro\n# Head"
        let storage = NSTextStorage(string: source)
        // Start from a full pass so the document has base attributes, then restyle at EOF
        // (the path that used to collapse to the first paragraph).
        MarkdownHighlighter.applyHighlighting(to: storage)
        // Wipe heading styling on the last paragraph only, then re-apply at caret-at-end.
        let lastPara = (source as NSString).range(of: "# Head")
        storage.setAttributes(MarkdownHighlighter.baseAttributes, range: lastPara)

        let end = NSRange(location: storage.length, length: 0)
        MarkdownHighlighter.applyHighlighting(to: storage, range: end)

        let headIndex = lastPara.location
        var range = NSRange(location: 0, length: 0)
        let headAttrs = storage.attributes(at: headIndex, effectiveRange: &range)
        assertColor(headAttrs[.foregroundColor], matches: LyraTheme.heading)
        let headFont = headAttrs[.font] as? NSFont
        XCTAssertEqual(headFont?.fontName, boldFont.fontName)

        let introAttrs = storage.attributes(at: 0, effectiveRange: &range)
        // Intro must not have picked up the heading colour (the old EOF bug).
        assertColorDoesNotMatch(introAttrs[.foregroundColor], LyraTheme.heading)
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

    // MARK: - Color helpers (dynamic NSColor is not reliably `==`)

    private func assertColor(
        _ actual: Any?,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let color = actual as? NSColor else {
            XCTFail("expected NSColor, got \(String(describing: actual))", file: file, line: line)
            return
        }
        let a = rgba(color)
        let e = rgba(expected)
        XCTAssertEqual(a.r, e.r, accuracy: 0.05, "red", file: file, line: line)
        XCTAssertEqual(a.g, e.g, accuracy: 0.05, "green", file: file, line: line)
        XCTAssertEqual(a.b, e.b, accuracy: 0.05, "blue", file: file, line: line)
    }

    private func assertColorDoesNotMatch(
        _ actual: Any?,
        _ unexpected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let color = actual as? NSColor else {
            // Missing colour is fine for "does not match heading".
            return
        }
        let a = rgba(color)
        let u = rgba(unexpected)
        let similar =
            abs(a.r - u.r) < 0.05
            && abs(a.g - u.g) < 0.05
            && abs(a.b - u.b) < 0.05
        XCTAssertFalse(similar, "colour unexpectedly matched heading token", file: file, line: line)
    }

    private func rgba(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        // Resolve dynamic catalogue colours under the current appearance.
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
