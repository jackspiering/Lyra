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
}
