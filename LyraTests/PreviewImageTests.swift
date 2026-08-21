import XCTest
@testable import Lyra

final class PreviewImageTests: XCTestCase {
    func testBudgetRejectsZeroAndHugeDimensions() {
        XCTAssertFalse(PreviewImage.isWithinBudget(width: 0, height: 10))
        XCTAssertFalse(PreviewImage.isWithinBudget(width: 10, height: 0))
        XCTAssertFalse(PreviewImage.isWithinBudget(width: PreviewImage.maxDecodedDimension + 1, height: 10))
        XCTAssertFalse(PreviewImage.isWithinBudget(width: 10_000, height: 10_000))
        XCTAssertTrue(PreviewImage.isWithinBudget(width: 1920, height: 1080))
    }

    func testDecodeRejectsOversizedPayloadWithoutRendering() {
        let huge = Data(count: PreviewImage.maxEncodedBytes + 1)
        XCTAssertNil(PreviewImage.decode(huge))
    }
}
