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
}
