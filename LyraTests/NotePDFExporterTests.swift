import XCTest
import PDFKit
@testable import Lyra

final class NotePDFExporterTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        return root
    }

    private func extractedText(from data: Data) throws -> String {
        let doc = try XCTUnwrap(PDFDocument(data: data))
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                parts.append(s)
            }
        }
        return parts.joined(separator: "\n")
    }

    func testSimpleNoteProducesPDFWithContent() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try NotePDFExporter.pdfData(
            markdown: "# Hello Heading\n\nHello world body",
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
        let text = try extractedText(from: data)
        XCTAssertTrue(text.contains("Hello Heading"), "got: \(text)")
        XCTAssertTrue(text.contains("Hello world body"), "got: \(text)")
    }

    func testEmptyMarkdownStillProducesPDF() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try NotePDFExporter.pdfData(
            markdown: "",
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
    }

    func testMissingImageDoesNotThrow() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let md = "# Title\n\n![missing](_attachments/nope.png)\n\nDone\n"
        let data = try NotePDFExporter.pdfData(
            markdown: md,
            noteDirectory: root,
            vaultRoot: root
        )
        let text = try extractedText(from: data)
        XCTAssertTrue(text.contains("Title") || text.contains("Done") || text.contains("Missing"), "got: \(text)")
    }

    func testLongCodeBlockSpansPagesAndKeepsLastLine() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var lines: [String] = ["```"]
        for i in 1...200 {
            lines.append("line-\(i)-content")
        }
        lines.append("```")
        let md = lines.joined(separator: "\n")
        let data = try NotePDFExporter.pdfData(markdown: md, noteDirectory: root, vaultRoot: root)
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(doc.pageCount, 1, "expected multi-page PDF for 200-line code fence")
        let text = try extractedText(from: data)
        XCTAssertTrue(text.contains("line-200-content"), "last code line missing; got: \(text.suffix(200))")
    }

    func testOversizedListItemSpansPagesWithoutDroppingTail() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let words = (1...500).map { "list-word-\($0)" }.joined(separator: " ")
        let data = try NotePDFExporter.pdfData(
            markdown: "- \(words)",
            noteDirectory: root,
            vaultRoot: root
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(doc.pageCount, 1)
        XCTAssertTrue(try extractedText(from: data).contains("list-word-500"))
    }

    func testOversizedQuoteSpansPagesWithoutDroppingTail() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let words = (1...500).map { "quote-word-\($0)" }.joined(separator: " ")
        let data = try NotePDFExporter.pdfData(
            markdown: "> \(words)",
            noteDirectory: root,
            vaultRoot: root
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(doc.pageCount, 1)
        XCTAssertTrue(try extractedText(from: data).contains("quote-word-500"))
    }

    func testUnicodeTextRemainsIntactAcrossPages() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = (1...600).map { "😀 café line \($0)" }.joined(separator: " ")
        let data = try NotePDFExporter.pdfData(
            markdown: source,
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertTrue(try extractedText(from: data).contains("😀 café line 600"))
    }

    func testInlineMarkdownStripsMarkers() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try NotePDFExporter.pdfData(
            markdown: "Heading with **bold** and a [link](https://example.com)",
            noteDirectory: root,
            vaultRoot: root
        )
        let text = try extractedText(from: data)
        XCTAssertFalse(text.contains("**"), "raw bold markers remain: \(text)")
        XCTAssertFalse(text.contains("]("), "raw link syntax remains: \(text)")
        XCTAssertTrue(text.contains("bold"), "got: \(text)")
    }

    func testExportStopsAtPageCap() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var lines: [String] = ["```"]
        for i in 1...400 {
            lines.append("page-cap-line-\(i)")
        }
        lines.append("```")
        let data = try NotePDFExporter.pdfData(
            markdown: lines.joined(separator: "\n"),
            noteDirectory: root,
            vaultRoot: root,
            maxPages: 2
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertLessThanOrEqual(doc.pageCount, 2)
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
        let text = try extractedText(from: data)
        XCTAssertTrue(
            text.contains("Export stopped at 2 pages"),
            "expected truncation notice; got: \(text.suffix(240))"
        )
    }

    func testCombinedNotesPDFContainsBothTitles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try NotePDFExporter.pdfData(
            notes: [
                .init(title: "AlphaNote", markdown: "body-a", noteDirectory: root),
                .init(title: "BetaNote", markdown: "body-b", noteDirectory: root),
            ],
            vaultRoot: root
        )
        let text = try extractedText(from: data)
        XCTAssertTrue(text.contains("AlphaNote"), "got: \(text)")
        XCTAssertTrue(text.contains("BetaNote"), "got: \(text)")
    }

    func testDocumentTitleIsWrittenToMetadata() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try NotePDFExporter.pdfData(
            markdown: "Body",
            noteDirectory: root,
            vaultRoot: root,
            documentTitle: "Roadmap"
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Roadmap")
    }

    func testItalicFaceIsItalic() {
        let font = LyraFonts.italic(size: 12)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic), "got \(font.fontName)")
    }
}
