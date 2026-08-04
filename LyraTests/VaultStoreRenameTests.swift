import XCTest
@testable import Lyra

final class VaultStoreRenameTests: XCTestCase {
    func testRejectsEmpty() {
        switch VaultStore.validatedRename("   ", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid(let msg): XCTAssertTrue(msg.contains("empty"))
        }
    }

    func testRejectsPathSeparators() {
        switch VaultStore.validatedRename("a/b.md", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid: break
        }
        switch VaultStore.validatedRename("a:b.md", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid: break
        }
    }

    func testRejectsLeadingDot() {
        switch VaultStore.validatedRename(".hidden.md", isDirectory: false) {
        case .ok: XCTFail("expected failure")
        case .invalid: break
        }
    }

    func testAppendsMarkdownExtensionForFiles() {
        XCTAssertEqual(VaultStore.validatedRename("Note", isDirectory: false), .ok("Note.md"))
        XCTAssertEqual(VaultStore.validatedRename("Note.md", isDirectory: false), .ok("Note.md"))
        XCTAssertEqual(VaultStore.validatedRename("Note.MD", isDirectory: false), .ok("Note.MD"))
    }

    func testFoldersKeepNameWithoutMd() {
        XCTAssertEqual(VaultStore.validatedRename("Projects", isDirectory: true), .ok("Projects"))
    }

    @MainActor
    func testRenameSelectedReturnsDestinationImmediately() throws {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let note = root.appendingPathComponent("alpha.md")
        try "hi".write(to: note, atomically: true, encoding: .utf8)

        let store = VaultStore()
        store.openVault(at: root)
        // Wait briefly for the initial scan so selectedNode can resolve.
        let deadline = Date().addingTimeInterval(2)
        while store.rootNode == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        store.selection = note.path
        // Even if the tree is still stale, rename must return the real destination URL.
        // Seed a minimal tree if scan has not landed yet.
        if store.selectedNode() == nil {
            store.rootNode = try FileSystemVault.scan(root: root)
            store.selection = note.path
        }

        let dest = try XCTUnwrap(store.renameSelected(to: "beta.md"))
        XCTAssertEqual(dest.lastPathComponent, "beta.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }
}
