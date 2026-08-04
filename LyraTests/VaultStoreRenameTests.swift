import XCTest
@testable import Lyra

final class VaultStoreRenameTests: XCTestCase {
    func testRejectsEmpty() {
        switch VaultStore.validatedRename("   ", isDirectory: false) {
        case .success: XCTFail("expected failure")
        case .failure(let msg): XCTAssertTrue(msg.contains("empty"))
        }
    }

    func testRejectsPathSeparators() {
        switch VaultStore.validatedRename("a/b.md", isDirectory: false) {
        case .success: XCTFail("expected failure")
        case .failure: break
        }
        switch VaultStore.validatedRename("a:b.md", isDirectory: false) {
        case .success: XCTFail("expected failure")
        case .failure: break
        }
    }

    func testRejectsLeadingDot() {
        switch VaultStore.validatedRename(".hidden.md", isDirectory: false) {
        case .success: XCTFail("expected failure")
        case .failure: break
        }
    }

    func testAppendsMarkdownExtensionForFiles() throws {
        XCTAssertEqual(try VaultStore.validatedRename("Note", isDirectory: false).get(), "Note.md")
        XCTAssertEqual(try VaultStore.validatedRename("Note.md", isDirectory: false).get(), "Note.md")
        XCTAssertEqual(try VaultStore.validatedRename("Note.MD", isDirectory: false).get(), "Note.MD")
    }

    func testFoldersKeepNameWithoutMd() throws {
        XCTAssertEqual(try VaultStore.validatedRename("Projects", isDirectory: true).get(), "Projects")
    }
}
