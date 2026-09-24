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
        XCTAssertNil(PreviewImage.imageSizeIfWithinBudget(huge))
    }

    func testDecodeValidPNGAndRejectsInvalidData() {
        let png = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        XCTAssertEqual(PreviewImage.imageSizeIfWithinBudget(png)?.width, 1)
        XCTAssertEqual(PreviewImage.imageSizeIfWithinBudget(png)?.height, 1)
        XCTAssertNotNil(PreviewImage.decode(png))
        XCTAssertNil(PreviewImage.decode(Data([0x00, 0x01, 0x02])))
    }
}
