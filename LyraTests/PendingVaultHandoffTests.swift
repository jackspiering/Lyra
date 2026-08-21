import XCTest
@testable import Lyra

final class PendingVaultHandoffTests: XCTestCase {
    func testTakeConsumesOnlyMatchingToken() {
        var handoff = PendingVaultHandoff()
        let a = URL(fileURLWithPath: "/tmp/vault-a")
        let b = URL(fileURLWithPath: "/tmp/vault-b")
        let idA = handoff.enqueue(a)
        let idB = handoff.enqueue(b)

        XCTAssertNil(handoff.take(UUID()), "unrelated window must not consume a pending pick")
        XCTAssertEqual(handoff.take(idB)?.path, b.path)
        XCTAssertEqual(handoff.take(idA)?.path, a.path)
        XCTAssertTrue(handoff.isEmpty)
        XCTAssertNil(handoff.take(idA), "token must not be reusable")
    }

    func testDiscardPreventsLaterConsume() {
        var handoff = PendingVaultHandoff()
        let url = URL(fileURLWithPath: "/tmp/vault-cancelled")
        let id = handoff.enqueue(url)
        handoff.discard(id)
        XCTAssertNil(handoff.take(id))
        XCTAssertTrue(handoff.isEmpty)
    }
}
