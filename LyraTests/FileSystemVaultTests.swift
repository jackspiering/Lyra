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

    func testScanSkipsFileSymlinks() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("lyra-outside-note-\(UUID().uuidString).md")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.md"),
            withDestinationURL: outside
        )

        let tree = try FileSystemVault.scan(root: root)
        XCTAssertFalse((tree.children ?? []).contains { $0.name == "linked.md" })
    }

    func testScanRejectsSymlinkedRoot() throws {
        let target = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: target) }
        let link = target.deletingLastPathComponent()
            .appendingPathComponent("lyra-root-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: link) }

        XCTAssertThrowsError(try FileSystemVault.scan(root: link))
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

    func testScanStopsAtMaxDepth() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        var current = root
        for name in ["a", "b", "c"] {
            current = current.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: current.appendingPathComponent("\(name).md").path,
                contents: Data("# \(name)".utf8),
                attributes: nil
            )
        }

        let shallow = try FileSystemVault.scanResult(root: root, maxDepth: 1)
        XCTAssertTrue(shallow.didTruncate)
        let urls = FileSystemVault.collectNoteURLs(from: shallow.node)
        let names = Set(urls.map(\.lastPathComponent))
        XCTAssertTrue(names.contains("a.md"))
        XCTAssertFalse(names.contains("c.md"))

        let deep = try FileSystemVault.scanResult(root: root, maxDepth: 8)
        XCTAssertFalse(deep.didTruncate)
        XCTAssertEqual(
            Set(FileSystemVault.collectNoteURLs(from: deep.node).map(\.lastPathComponent)),
            Set(["a.md", "b.md", "c.md"])
        )
    }

    func testIndexedUTF8BodySkipsOversizedFiles() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let small = root.appendingPathComponent("small.md")
        try "hello".write(to: small, atomically: true, encoding: .utf8)
        XCTAssertEqual(FileSystemVault.indexedUTF8Body(at: small, maxBytes: 16), .body("hello"))

        let large = root.appendingPathComponent("large.md")
        try String(repeating: "x", count: 64).write(to: large, atomically: true, encoding: .utf8)
        XCTAssertEqual(FileSystemVault.indexedUTF8Body(at: large, maxBytes: 16), .oversized)

        let invalid = root.appendingPathComponent("invalid.md")
        try Data([0xFF, 0xFE]).write(to: invalid)
        XCTAssertEqual(FileSystemVault.indexedUTF8Body(at: invalid, maxBytes: 16), .unreadable)

        let missing = root.appendingPathComponent("missing.md")
        XCTAssertEqual(FileSystemVault.indexedUTF8Body(at: missing, maxBytes: 16), .unreadable)
    }

    func testRelativePathUsesPathComponents() {
        let root = URL(fileURLWithPath: "/vault/Notes")
        XCTAssertEqual(
            FileSystemVault.relativePath(
                for: URL(fileURLWithPath: "/vault/Notes2/x.md"),
                under: root
            ),
            "x.md"
        )
        XCTAssertEqual(
            FileSystemVault.relativePath(
                for: URL(fileURLWithPath: "/vault/Notes/Projects/x.md"),
                under: root
            ),
            "Projects/x.md"
        )
    }

    func testRootIsNotAStrictDescendant() {
        let root = URL(fileURLWithPath: "/vault")
        XCTAssertFalse(FileSystemVault.isStrictDescendant(root, root: root))
        XCTAssertTrue(
            FileSystemVault.isStrictDescendant(
                URL(fileURLWithPath: "/vault/note.md"),
                root: root
            )
        )
    }

    func testNoteCountCountsNestedNotesOnly() {
        let root = URL(fileURLWithPath: "/vault")
        let note = { (name: String) in
            VaultNode(name: name, url: root.appendingPathComponent(name), isDirectory: false, children: nil)
        }
        let tree = VaultNode(name: "vault", url: root, isDirectory: true, children: [
            note("A.md"),
            VaultNode(name: "Sub", url: root.appendingPathComponent("Sub"), isDirectory: true, children: [
                note("B.md"),
                VaultNode(name: "Empty", url: root.appendingPathComponent("Sub/Empty"), isDirectory: true, children: []),
            ]),
        ])
        XCTAssertEqual(tree.noteCount, 2)
        XCTAssertEqual(tree.children?[1].noteCount, 1)
        XCTAssertEqual(note("C.md").noteCount, 1)
    }

    func testCaseOnlyMoveRenamesFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("case-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lower = root.appendingPathComponent("note.md")
        try "body".write(to: lower, atomically: true, encoding: .utf8)

        let upper = root.appendingPathComponent("Note.md")
        try FileSystemVault.move(lower, to: upper)

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names, ["Note.md"])
        XCTAssertEqual(try String(contentsOf: upper, encoding: .utf8), "body")
    }

    func testMoveRefusesExistingDifferentFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("move-exists-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.md")
        let b = root.appendingPathComponent("b.md")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try FileSystemVault.move(a, to: b))
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "b")
    }
}
