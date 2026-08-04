import XCTest
@testable import Lyra

final class MarkdownImagePathTests: XCTestCase {
    func testResolveVaultRelativeAttachments() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let attachments = root.appendingPathComponent("_attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let file = attachments.appendingPathComponent("a.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

        let noteDir = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        let url = MarkdownImagePath.resolve(
            path: "_attachments/a.png",
            noteDirectory: noteDir,
            vaultRoot: root
        )
        XCTAssertEqual(url?.path, file.path)
    }

    func testResolveNoteRelativeFirst() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let noteDir = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        let noteLocal = noteDir.appendingPathComponent("photo.png")
        try Data([0x01]).write(to: noteLocal)

        // Same relative path also under vault root — note dir must win.
        try Data([0x02]).write(to: root.appendingPathComponent("photo.png"))

        let url = MarkdownImagePath.resolve(
            path: "photo.png",
            noteDirectory: noteDir,
            vaultRoot: root
        )
        XCTAssertEqual(url?.path, noteLocal.path)
    }

    func testResolveAbsolutePathWhenExists() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let absFile = root.appendingPathComponent("abs.png")
        try Data([0x03]).write(to: absFile)

        let url = MarkdownImagePath.resolve(
            path: absFile.path,
            noteDirectory: root,
            vaultRoot: root
        )
        XCTAssertEqual(url?.path, absFile.path)
    }

    func testResolveMissingReturnsNil() {
        let vault = URL(fileURLWithPath: "/tmp/lyra-missing-vault-\(UUID().uuidString)")
        let noteDir = vault.appendingPathComponent("notes")
        let url = MarkdownImagePath.resolve(
            path: "_attachments/nope.png",
            noteDirectory: noteDir,
            vaultRoot: vault
        )
        XCTAssertNil(url)
    }

    func testParseImageLine() {
        let r = MarkdownImagePath.parseImageLine("![hi](_attachments/x.png)")
        XCTAssertEqual(r?.alt, "hi")
        XCTAssertEqual(r?.path, "_attachments/x.png")
    }

    func testParseImageLineEmptyAlt() {
        let r = MarkdownImagePath.parseImageLine("![](_attachments/y.png)")
        XCTAssertEqual(r?.alt, "")
        XCTAssertEqual(r?.path, "_attachments/y.png")
    }

    func testParseImageLineRejectsPartial() {
        XCTAssertNil(MarkdownImagePath.parseImageLine("see ![hi](x.png) more"))
        XCTAssertNil(MarkdownImagePath.parseImageLine("![hi](x.png) trailing"))
        XCTAssertNil(MarkdownImagePath.parseImageLine("[hi](x.png)"))
    }

    func testResolvePercentEncodedNoteRelative() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let attachments = root.appendingPathComponent("_attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let file = attachments.appendingPathComponent("pasted-image-1.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

        let noteDir = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        // Explicit %2F encoding (not only path-safe chars left unescaped by urlPathAllowed).
        let encoded = "..%2F_attachments%2Fpasted-image-1.png"
        let url = MarkdownImagePath.resolve(
            path: encoded,
            noteDirectory: noteDir,
            vaultRoot: root
        )
        // `..` relatives may keep `..` in URL.path; compare resolved filesystem paths.
        XCTAssertEqual(
            url?.resolvingSymlinksInPath().standardizedFileURL.path,
            file.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }
}
