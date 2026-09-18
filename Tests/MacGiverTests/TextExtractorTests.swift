import CoreGraphics
import XCTest
@testable import MacGiver

final class TextExtractorTests: XCTestCase {
    func testDefaultShortcutIsCommandShift7() {
        XCTAssertEqual(TextExtractorShortcut.defaultValue.keyCode, 26)
        XCTAssertEqual(TextExtractorShortcut.defaultValue.displayString, "⇧⌘7")
        XCTAssertTrue(TextExtractorShortcut.defaultValue.isValid)
    }

    func testShortcutRoundTripsThroughUserDefaults() {
        let suiteName = "MacGiverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortcut = TextExtractorShortcut(keyCode: 12, modifiers: TextExtractorShortcut.defaultValue.modifiers, keyName: "Q")
        shortcut.save(to: defaults)

        XCTAssertEqual(TextExtractorShortcut.load(from: defaults), shortcut)
    }

    func testShortcutRequiresACommandControlOrOptionModifier() {
        XCTAssertFalse(TextExtractorShortcut(keyCode: 26, modifiers: 0).isValid)
    }

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
