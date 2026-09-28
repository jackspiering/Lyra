import XCTest
@testable import Lyra

final class VaultBookmarkRestoreTests: XCTestCase {
    func testFreshBookmarkAutoOpens() {
        let decision = VaultBookmarkRestore.decision(didResolve: true, isStale: false)
        XCTAssertEqual(decision, .autoOpen)
    }

    func testStaleBookmarkPromptsUser() {
        let decision = VaultBookmarkRestore.decision(didResolve: true, isStale: true)
        XCTAssertEqual(decision, .promptUser)
    }

    func testUnresolvedBookmarkIsSkipped() {
        XCTAssertEqual(
            VaultBookmarkRestore.decision(didResolve: false, isStale: true),
            .skip
        )
    }
}
