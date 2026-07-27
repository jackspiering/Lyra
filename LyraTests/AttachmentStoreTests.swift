import XCTest
@testable import Lyra

final class AttachmentStoreTests: XCTestCase {
    func testUniqueFilenameFormat() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 27
        c.hour = 15; c.minute = 30; c.second = 45
        let date = cal.date(from: c)!
        let name = AttachmentStore.uniquePNGFilename(now: date, existing: [])
        XCTAssertEqual(name, "Pasted Image 20260727-153045.png")
    }

    func testUniqueFilenameCollisionSuffix() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 27
        c.hour = 15; c.minute = 30; c.second = 45
        let date = cal.date(from: c)!
        let base = "Pasted Image 20260727-153045.png"
        let name = AttachmentStore.uniquePNGFilename(
            now: date,
            existing: [base, "Pasted Image 20260727-153045-2.png"]
        )
        XCTAssertEqual(name, "Pasted Image 20260727-153045-3.png")
    }

    func testSavePNGCreatesFolderAndReturnsRelativePath() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // 1x1 PNG
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let rel = try AttachmentStore.savePNG(data: png, vaultRoot: root)
        XCTAssertTrue(rel.hasPrefix("_attachments/"))
        XCTAssertTrue(rel.hasSuffix(".png"))
        let file = root.appendingPathComponent(rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
