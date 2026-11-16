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
        switch FilenameValidation.validate("_attachments", isDirectory: true) {
        case .ok: XCTFail("expected reserved attachment folder rejection")
        case .invalid: break
        }
    }

    func testSanitizeNoteStem() {
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("Note"), "Note")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("  Note  "), "Note")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("Note.md"), "Note")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("Note.MD"), "Note")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("   "), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem(""), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("a/b"), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("a:b"), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("note\u{0000}"), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem(".hidden"), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("."), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem(".."), "Untitled")
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem(".md"), "Untitled")
    }

    func testNoteNamesRejectWikiLinkSyntax() {
        for name in ["C# Notes", "A|B", "Draft [v2]", "a]b.md", "x[y"] {
            switch FilenameValidation.validate(name, isDirectory: false) {
            case .ok(let accepted): XCTFail("expected \(name) to be rejected, got \(accepted)")
            case .invalid(let message): XCTAssertTrue(message.contains("[[links]]"), message)
            }
        }
        // Other punctuation still makes a linkable name.
        XCTAssertEqual(
            FilenameValidation.validate("Q&A ^ notes (2026)", isDirectory: false),
            .ok("Q&A ^ notes (2026).md")
        )
        XCTAssertEqual(FilenameValidation.sanitizeNoteStem("Note #1"), "Untitled")
    }

    func testFolderNamesMayContainWikiLinkSyntax() {
        XCTAssertEqual(FilenameValidation.validate("C# [old]", isDirectory: true), .ok("C# [old]"))
    }
}
