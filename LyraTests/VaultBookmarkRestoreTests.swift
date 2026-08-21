import XCTest
@testable import Lyra

final class VaultBookmarkRestoreTests: XCTestCase {
    func testFreshBookmarkAutoOpensAndPersists() {
        let decision = VaultBookmarkRestore.decision(didResolve: true, isStale: false)
        XCTAssertEqual(decision, .autoOpen)
        XCTAssertTrue(VaultBookmarkRestore.shouldPersistOnRestore(decision))
    }

    func testStaleBookmarkPromptsAndDoesNotPersist() {
        let decision = VaultBookmarkRestore.decision(didResolve: true, isStale: true)
        XCTAssertEqual(decision, .promptUser)
        XCTAssertFalse(
            VaultBookmarkRestore.shouldPersistOnRestore(decision),
            "stale bookmarks must not be rewritten without user confirmation"
        )
    }

    func testUnresolvedBookmarkIsSkipped() {
        XCTAssertEqual(
            VaultBookmarkRestore.decision(didResolve: false, isStale: true),
            .skip
        )
        XCTAssertFalse(VaultBookmarkRestore.shouldPersistOnRestore(.skip))
    }
}
