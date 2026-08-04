import XCTest
@testable import Lyra

final class FileSystemVaultTests: XCTestCase {
    func testShouldInclude() {
        XCTAssertFalse(FileSystemVault.shouldInclude(name: ".git"))
        XCTAssertFalse(FileSystemVault.shouldInclude(name: ".DS_Store"))
        XCTAssertFalse(FileSystemVault.shouldInclude(name: ".hidden"))
        XCTAssertTrue(FileSystemVault.shouldInclude(name: "Note.md"))
        XCTAssertTrue(FileSystemVault.shouldInclude(name: "folder"))
    }

    func testScanFindsNestedMarkdownAndSkipsIgnored() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sub = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: sub.appendingPathComponent("a.md").path,
            contents: Data("# A".utf8),
            attributes: nil
        )
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("root.md").path,
            contents: Data("# R".utf8),
            attributes: nil
        )
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("skip.txt").path,
            contents: Data(),
            attributes: nil
        )
        FileManager.default.createFile(
            atPath: root.appendingPathComponent(".DS_Store").path,
            contents: Data(),
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )

        let tree = try FileSystemVault.scan(root: root)
        XCTAssertTrue(tree.isDirectory)

        let names = Set((tree.children ?? []).map(\.name))
        XCTAssertTrue(names.contains("notes"))
        XCTAssertTrue(names.contains("root.md"))
        XCTAssertFalse(names.contains("skip.txt"))
        XCTAssertFalse(names.contains(".DS_Store"))
        XCTAssertFalse(names.contains(".git"))

        let notesFolder = (tree.children ?? []).first { $0.name == "notes" }
        XCTAssertEqual(notesFolder?.children?.map(\.name), ["a.md"])

        let urls = FileSystemVault.collectNoteURLs(from: tree)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), Set(["a.md", "root.md"]))
    }

    func testScanHidesAttachmentsFolder() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(
            atPath: root.appendingPathComponent("note.md").path,
            contents: Data("# Note".utf8),
            attributes: nil
        )
        let attachments = root.appendingPathComponent(AttachmentStore.folderName)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: attachments.appendingPathComponent("foo.png").path,
            contents: Data(),
            attributes: nil
        )

        let tree = try FileSystemVault.scan(root: root)
        let names = (tree.children ?? []).map(\.name)
        XCTAssertTrue(names.contains("note.md"))
        XCTAssertFalse(names.contains("_attachments"))
        XCTAssertFalse(names.contains(AttachmentStore.folderName))
    }

    func testScanSkipsDirectorySymlinkLoops() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(
            atPath: root.appendingPathComponent("note.md").path,
            contents: Data("# Note".utf8),
            attributes: nil
        )
        let loop = root.appendingPathComponent("loop")
        // Symlink to parent would recurse forever without a guard.
        try FileManager.default.createSymbolicLink(
            at: loop,
            withDestinationURL: root
        )

        let tree = try FileSystemVault.scan(root: root)
        let names = (tree.children ?? []).map(\.name)
        XCTAssertTrue(names.contains("note.md"))
        XCTAssertFalse(names.contains("loop"))
    }

    func testScanSkipsUnreadableChildButKeepsSiblings() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer {
            // Restore perms so cleanup can delete.
            let locked = root.appendingPathComponent("locked")
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }

        FileManager.default.createFile(
            atPath: root.appendingPathComponent("keeper.md").path,
            contents: Data("# K".utf8),
            attributes: nil
        )
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: locked.appendingPathComponent("secret.md").path,
            contents: Data("# S".utf8),
            attributes: nil
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let tree = try FileSystemVault.scan(root: root)
        let names = Set((tree.children ?? []).map(\.name))
        XCTAssertTrue(names.contains("keeper.md"))
        // locked may be absent (skipped on recurse) or present empty — either way keeper survives.
        XCTAssertFalse(names.contains("secret.md"))
    }
}
