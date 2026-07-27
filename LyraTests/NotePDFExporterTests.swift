import XCTest
@testable import Lyra

final class NotePDFExporterTests: XCTestCase {
    func testSimpleNoteProducesPDFData() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try NotePDFExporter.pdfData(
            markdown: "# Hi\n\nHello",
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertGreaterThan(data.count, 100)
        let header = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    func testEmptyMarkdownStillProducesPDF() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try NotePDFExporter.pdfData(
            markdown: "",
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertGreaterThan(data.count, 50)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }

    func testMissingImageDoesNotThrow() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let md = "# Title\n\n![missing](_attachments/nope.png)\n\nDone\n"
        let data = try NotePDFExporter.pdfData(
            markdown: md,
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }
}
