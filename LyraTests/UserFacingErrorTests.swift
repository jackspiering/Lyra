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
        XCTAssertTrue(message.contains("permission") || message.contains("Permission"))
        XCTAssertTrue(message.contains("⌘V") || message.contains("paste"))
        XCTAssertFalse(message.contains("NSCocoaErrorDomain"))
    }

    func testMissingFileError() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileNoSuchFileError,
            userInfo: [:]
        )
        let pair = UserFacingError.presentable(for: error, context: .openNote)
        XCTAssertEqual(pair.title, "Couldn't open note")
        XCTAssertTrue(pair.message.contains("could not be found") || pair.message.contains("moved"))
    }

    func testOutOfSpaceIncludesTip() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError,
            userInfo: [:]
        )
        let message = UserFacingError.message(for: error, context: .exportPDF)
        XCTAssertTrue(message.contains("space") || message.contains("Space"))
        XCTAssertTrue(message.contains("save location") || message.contains("disk"))
    }

    func testContextTitlesAreShort() {
        for context in [
            UserFacingError.Context.saveNote,
            .pasteImage,
            .exportPDF,
            .rename,
        ] {
            XCTAssertLessThan(context.title.count, 40)
            XCTAssertTrue(context.title.contains("Couldn't") || context.title.hasPrefix("Could"))
        }
    }
}
