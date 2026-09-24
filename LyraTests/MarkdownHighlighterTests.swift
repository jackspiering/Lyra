import XCTest
import AppKit
@testable import Lyra

final class MarkdownHighlighterTests: XCTestCase {
    private var boldFont: NSFont { LyraFonts.ui(size: LyraFonts.proseSize, weight: .bold) }
    private var baseFont: NSFont { LyraFonts.ui(size: LyraFonts.proseSize) }

    override func setUp() {
        super.setUp()
        // Unit tests may not run through LyraApp.init.
        LyraFonts.registerBundledFonts()
    }

    func testHeadingRuleAppliesBoldFontAndHeadingColor() {
        let storage = NSTextStorage(string: "# Title\nplain")
        MarkdownHighlighter.applyHighlighting(to: storage)

        var range = NSRange(location: 0, length: 0)
        let titleIndex = (storage.string as NSString).range(of: "Title").location
        let headingAttrs = storage.attributes(at: titleIndex, effectiveRange: &range)
        let headingFont = headingAttrs[.font] as? NSFont
        XCTAssertEqual(headingFont?.fontName, boldFont.fontName)
        XCTAssertEqual(headingFont?.pointSize, LyraFonts.headingSize(level: 1))
        assertColor(headingAttrs[.foregroundColor], matches: LyraTheme.heading)

        let plainIndex = (storage.string as NSString).range(of: "plain").location
        let plainAttrs = storage.attributes(at: plainIndex, effectiveRange: &range)
        let plainFont = plainAttrs[.font] as? NSFont
        XCTAssertEqual(plainFont?.fontName, baseFont.fontName)
        // Plain body uses the ink token, not the heading token.
        assertColor(plainAttrs[.foregroundColor], matches: LyraTheme.ink)
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

        let headIndex = lastPara.location + 2
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

    func testReplacementRangeRestylesEveryEditedParagraph() {
        let storage = NSTextStorage(string: "before\nplain\nafter")
        MarkdownHighlighter.applyHighlighting(to: storage)

        let old = (storage.string as NSString).range(of: "plain")
        let replacement = "## heading\n**bold**"
        storage.replaceCharacters(in: old, with: replacement)
        MarkdownHighlighter.applyHighlighting(
            to: storage,
            range: NSRange(location: old.location, length: (replacement as NSString).length)
        )

        var range = NSRange(location: 0, length: 0)
        let heading = storage.attributes(at: old.location, effectiveRange: &range)
        XCTAssertEqual((heading[.font] as? NSFont)?.fontName, boldFont.fontName)

        let boldIndex = (storage.string as NSString).range(of: "**bold**").location
        let bold = storage.attributes(at: boldIndex, effectiveRange: &range)
        XCTAssertEqual((bold[.font] as? NSFont)?.fontName, boldFont.fontName)

        let beforeAttrs = storage.attributes(at: 0, effectiveRange: &range)
        assertColorDoesNotMatch(beforeAttrs[.foregroundColor], LyraTheme.heading)
    }

    func testHeadingMarkersAreDimmedAndSizedByLevel() {
        let storage = NSTextStorage(string: "### Third")
        MarkdownHighlighter.applyHighlighting(to: storage)
        var range = NSRange(location: 0, length: 0)
        let hashes = storage.attributes(at: 0, effectiveRange: &range)
        assertColor(hashes[.foregroundColor], matches: LyraTheme.markup)
        XCTAssertEqual((hashes[.font] as? NSFont)?.pointSize, LyraFonts.headingSize(level: 3))
    }

    func testBoldInsideHeadingKeepsHeadingSize() {
        let storage = NSTextStorage(string: "## A **big** idea")
        MarkdownHighlighter.applyHighlighting(to: storage)
        let index = (storage.string as NSString).range(of: "big").location
        var range = NSRange(location: 0, length: 0)
        let font = storage.attributes(at: index, effectiveRange: &range)[.font] as? NSFont
        XCTAssertEqual(font?.fontName, boldFont.fontName)
        XCTAssertEqual(font?.pointSize, LyraFonts.headingSize(level: 2))
    }

    func testWikiBracketsAreMarkupAndTargetIsAccent() {
        let storage = NSTextStorage(string: "see [[Other Note]] now")
        MarkdownHighlighter.applyHighlighting(to: storage)
        let ns = storage.string as NSString
        var range = NSRange(location: 0, length: 0)
        let bracket = storage.attributes(at: ns.range(of: "[[").location, effectiveRange: &range)
        assertColor(bracket[.foregroundColor], matches: LyraTheme.markup)
        let target = storage.attributes(at: ns.range(of: "Other").location, effectiveRange: &range)
        assertColor(target[.foregroundColor], matches: LyraTheme.wiki)
        XCTAssertNotNil(target[.underlineStyle])
    }

    func testInlineCodeUsesMonospacedFontWithoutChangingText() {
        let source = "run `grep` here"
        let storage = NSTextStorage(string: source)
        MarkdownHighlighter.applyHighlighting(to: storage)
        XCTAssertEqual(storage.string, source)
        let index = (source as NSString).range(of: "grep").location
        var range = NSRange(location: 0, length: 0)
        let font = storage.attributes(at: index, effectiveRange: &range)[.font] as? NSFont
        let isMonospaced = font?.isFixedPitch == true
            || font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true
        XCTAssertTrue(isMonospaced)
    }

    func testFencedCodeDoesNotReceiveMarkdownStyling() {
        let source = "```\n# Not a heading\n**Not bold**\n```"
        let storage = NSTextStorage(string: source)
        MarkdownHighlighter.applyHighlighting(to: storage)

        let ns = source as NSString
        var range = NSRange(location: 0, length: 0)
        let headingAttrs = storage.attributes(at: ns.range(of: "Not a heading").location, effectiveRange: &range)
        assertColorDoesNotMatch(headingAttrs[.foregroundColor], LyraTheme.heading)
        assertColor(headingAttrs[.foregroundColor], matches: LyraTheme.code)
    }

    func testBodyCarriesProseLineSpacing() {
        let storage = NSTextStorage(string: "plain")
        MarkdownHighlighter.applyHighlighting(to: storage)
        var range = NSRange(location: 0, length: 0)
        let style = storage.attributes(at: 0, effectiveRange: &range)[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(style?.lineSpacing, LyraFonts.proseLineSpacing)
    }

    func testColumnInsetCentersWideWindowsAndKeepsMarginInNarrowOnes() {
        let wide = LyraTheme.columnWidth + 400
        XCTAssertEqual(LyraTheme.columnInset(forWidth: wide), 200)
        XCTAssertEqual(LyraTheme.columnInset(forWidth: 500), LyraTheme.columnMargin)
        XCTAssertEqual(LyraTheme.columnInset(forWidth: 0), LyraTheme.columnMargin)
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
