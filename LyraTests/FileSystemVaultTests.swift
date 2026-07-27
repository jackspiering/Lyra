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

    func testReadWriteUTF8() throws {
        let dir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("t.md")
        try FileSystemVault.writeUTF8("hello", to: url)
        XCTAssertEqual(try FileSystemVault.readUTF8(from: url), "hello")
    }
}
