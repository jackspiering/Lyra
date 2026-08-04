import XCTest
@testable import Lyra

final class UserFacingErrorTests: XCTestCase {
    func testPermissionErrorIsPlainLanguage() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "You don’t have permission."]
        )
        let message = UserFacingError.message(for: error, context: .pasteImage)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("permission"))
        XCTAssertTrue(message.contains("⌘V") || message.localizedCaseInsensitiveContains("paste"))
        XCTAssertFalse(message.contains("NSCocoaErrorDomain"))
    }

    func testMissingFileError() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [:])
        let pair = UserFacingError.presentable(for: error, context: .openNote)
        XCTAssertEqual(pair.title, "Couldn't open note")
        XCTAssertTrue(pair.message.localizedCaseInsensitiveContains("found")
            || pair.message.localizedCaseInsensitiveContains("moved"))
    }

    func testOutOfSpaceIncludesTip() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [:])
        let message = UserFacingError.message(for: error, context: .exportPDF)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("space"))
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("export")
                || message.localizedCaseInsensitiveContains("PDF")
                || message.localizedCaseInsensitiveContains("disk"),
            "expected context tip; got: \(message)"
        )
    }

    func testPOSIXPermissionMapsWithoutCocoaDomainLeak() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [:])
        let message = UserFacingError.message(for: error, context: .saveNote)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("permission"), "got: \(message)")
        XCTAssertFalse(message.contains("NSPOSIXErrorDomain"))
        XCTAssertFalse(message.contains("EACCES"))
    }

    func testFileExistsMapsToPlainLanguage() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: [:])
        let message = UserFacingError.message(for: error, context: .createNote)
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("exist")
                || message.localizedCaseInsensitiveContains("already"),
            "got: \(message)"
        )
    }
}
