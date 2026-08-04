import XCTest
@testable import Lyra

final class FilenameValidationTests: XCTestCase {
    func testRejectsEmptyAndIllegalMacCharacters() {
        switch FilenameValidation.validate("   ", isDirectory: false) {
        case .ok: XCTFail("expected empty rejection")
        case .invalid(let msg): XCTAssertTrue(msg.contains("empty"))
        }

        switch FilenameValidation.validate("a/b.md", isDirectory: false) {
        case .ok: XCTFail("expected / rejection")
        case .invalid: break
        }

        switch FilenameValidation.validate("a:b.md", isDirectory: false) {
        case .ok: XCTFail("expected : rejection")
        case .invalid: break
        }

        switch FilenameValidation.validate("note\u{0000}.md", isDirectory: false) {
        case .ok: XCTFail("expected control character rejection")
        case .invalid(let msg): XCTAssertTrue(msg.lowercased().contains("control"))
        }

        switch FilenameValidation.validate(".", isDirectory: true) {
        case .ok: XCTFail("expected . rejection")
        case .invalid: break
        }

        switch FilenameValidation.validate("..", isDirectory: true) {
        case .ok: XCTFail("expected .. rejection")
        case .invalid: break
        }

        switch FilenameValidation.validate(".hidden.md", isDirectory: false) {
        case .ok: XCTFail("expected leading-dot rejection")
        case .invalid: break
        }
    }

    func testNoteGetsMdSuffix() {
        XCTAssertEqual(FilenameValidation.validate("Note", isDirectory: false), .ok("Note.md"))
        XCTAssertEqual(FilenameValidation.validate("Note.md", isDirectory: false), .ok("Note.md"))
        XCTAssertEqual(FilenameValidation.validate("Note.MD", isDirectory: false), .ok("Note.MD"))
    }

    func testFoldersKeepNameWithoutMd() {
        XCTAssertEqual(FilenameValidation.validate("Projects", isDirectory: true), .ok("Projects"))
    }

    func testVaultStoreValidatedRenameDelegates() {
        XCTAssertEqual(
            VaultStore.validatedRename("Note", isDirectory: false),
            FilenameValidation.validate("Note", isDirectory: false)
        )
        XCTAssertEqual(
            VaultStore.validatedRename("a/b", isDirectory: false),
            FilenameValidation.validate("a/b", isDirectory: false)
        )
    }
}
