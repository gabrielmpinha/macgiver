import CoreGraphics
import XCTest
@testable import MacGiver

final class TextExtractorTests: XCTestCase {
    func testOCRLinesAreTrimmedAndJoined() {
        XCTAssertEqual(
            TextRecognitionService.normalizedText(["  First line ", "", "Second line\n"]),
            "First line\nSecond line"
        )
    }

    func testOCRReturnsNoTextForBlankLines() {
        XCTAssertNil(TextRecognitionService.normalizedText(["", "  \n"]))
    }

    func testScreenSelectionMapsToRetinaPixelsFromTopLeft() {
        let crop = ScreenCapture.pixelCropRect(
            imageSize: CGSize(width: 2_000, height: 1_600),
            selection: CGRect(x: 100, y: 150, width: 300, height: 200),
            screenFrame: CGRect(x: -1_440, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(crop, CGRect(x: 200, y: 900, width: 600, height: 400))
    }
}
