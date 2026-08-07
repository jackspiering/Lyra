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
        XCTAssertEqual(name, "pasted-image-20260727-153045.png")
        XCTAssertFalse(name.contains(" "))
    }

    func testUniqueFilenameCollisionSuffix() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 27
        c.hour = 15; c.minute = 30; c.second = 45
        let date = cal.date(from: c)!
        let base = "pasted-image-20260727-153045.png"
        let name = AttachmentStore.uniquePNGFilename(
            now: date,
            existing: [base, "pasted-image-20260727-153045-2.png"]
        )
        XCTAssertEqual(name, "pasted-image-20260727-153045-3.png")
        XCTAssertFalse(name.contains(" "))
    }

    func testUniqueFilenameTreatsCaseVariantAsCollision() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 27
        components.hour = 15
        components.minute = 30
        components.second = 45
        let date = calendar.date(from: components)!
        let name = AttachmentStore.uniquePNGFilename(
            now: date,
            existing: ["PASTED-IMAGE-20260727-153045.PNG"]
        )
        XCTAssertNotEqual(name.lowercased(), "pasted-image-20260727-153045.png")
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
        XCTAssertFalse(rel.contains(" "), "Markdown link destinations must not contain spaces")
        let file = root.appendingPathComponent(rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testSavePNGNoteRelativeFromNestedFolder() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let noteDir = root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
        let noteURL = noteDir.appendingPathComponent("note.md")
        try "# Note".write(to: noteURL, atomically: true, encoding: .utf8)

        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let rel = try AttachmentStore.savePNG(data: png, vaultRoot: root, noteURL: noteURL)
        XCTAssertFalse(rel.contains(" "), "link path must have no spaces")
        XCTAssertTrue(rel.contains("_attachments/"))
        XCTAssertTrue(rel.hasPrefix("../"), "nested note should use parent-relative path")

        let resolved = MarkdownImagePath.resolve(
            path: rel,
            noteDirectory: noteDir,
            vaultRoot: root
        )
        XCTAssertNotNil(resolved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved!.path))
    }

    func testSavePNGRejectsAttachmentsSymlink() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("lyra-outside-attachments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(AttachmentStore.folderName),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try AttachmentStore.savePNG(data: Data([0x01]), vaultRoot: root)
        )
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: outside.path))?.isEmpty == true)
    }

    func testRelativePathHelper() {
        let vault = URL(fileURLWithPath: "/tmp/vault")
        let noteDir = vault.appendingPathComponent("projects", isDirectory: true)
        let attach = vault
            .appendingPathComponent("_attachments", isDirectory: true)
            .appendingPathComponent("pasted-image.png")
        let rel = AttachmentStore.relativePath(from: noteDir, to: attach)
        XCTAssertEqual(rel, "../_attachments/pasted-image.png")
    }
}
