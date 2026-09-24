import AppKit
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

    func testDownsampledDecodeKeepsPointSize() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 1500,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        let image = try XCTUnwrap(PreviewImage.decode(png, maxPixelSize: 600))
        XCTAssertEqual(image.size, NSSize(width: 3000, height: 1500))
        let (bitmap, size) = try XCTUnwrap(PreviewImage.decodeBitmap(png, maxPixelSize: 600))
        XCTAssertEqual(size.width, 3000)
        XCTAssertLessThanOrEqual(max(bitmap.width, bitmap.height), 600)
    }
}
