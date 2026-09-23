import CoreGraphics
import ScreenCaptureKit
import XCTest
@testable import MacGiver

final class TextExtractorTests: XCTestCase {
    func testOnlyScreenCaptureKitPermissionDenialRequestsAuthorization() {
        XCTAssertEqual(ScreenCapture.failure(for: NSError(
            domain: SCStreamErrorDomain, code: SCStreamError.userDeclined.rawValue
        )), .permissionDenied)
        XCTAssertEqual(ScreenCapture.failure(for: NSError(
            domain: SCStreamErrorDomain, code: SCStreamError.internalError.rawValue
        )), .unavailable)
        XCTAssertEqual(ScreenCapture.failure(for: NSError(
            domain: "UnrelatedCaptureError", code: SCStreamError.userDeclined.rawValue
        )), .unavailable)
    }

    @MainActor
    func testCaptureRequestDeliversSuccessfulImage() async throws {
        let image = try testImage()
        let request = ScreenCaptureRequest()
        var delivered: CGImage?
        let task = request.start(operation: { image }, completion: { result in
            delivered = try? result.get()
        })
        await task.value
        XCTAssertTrue(delivered === image)
    }

    @MainActor
    func testCapturePreservesPermissionAndOtherErrors() async {
        for code in [SCStreamError.userDeclined.rawValue, SCStreamError.internalError.rawValue] {
            let request = ScreenCaptureRequest()
            var delivered: NSError?
            let task = request.start(operation: {
                throw NSError(domain: SCStreamErrorDomain, code: code)
            }, completion: { result in
                if case .failure(let error) = result { delivered = error as NSError }
            })
            await task.value
            XCTAssertEqual(delivered?.domain, SCStreamErrorDomain)
            XCTAssertEqual(delivered?.code, code)
        }
    }

    @MainActor
    func testSupersededCaptureIgnoresLateSuccessAndFailure() async throws {
        let image = try testImage()
        for failOldRequest in [false, true] {
            let request = ScreenCaptureRequest()
            var continuation: CheckedContinuation<CGImage, Error>?
            let started = expectation(description: "First capture started")
            var completions: [String] = []
            let oldTask = request.start(operation: {
                try await withCheckedThrowingContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }, completion: { _ in completions.append("old") })
            await fulfillment(of: [started], timeout: 2)
            let newTask = request.start(operation: { image }, completion: { _ in
                completions.append("new")
            })
            await newTask.value
            let pending = try XCTUnwrap(continuation)
            if failOldRequest {
                pending.resume(throwing: NSError(domain: SCStreamErrorDomain, code: SCStreamError.userDeclined.rawValue))
            } else {
                pending.resume(returning: image)
            }
            await oldTask.value
            XCTAssertEqual(completions, ["new"])
        }
    }

    @MainActor
    func testCancelledCaptureDoesNotPresentAResult() async throws {
        let image = try testImage()
        let request = ScreenCaptureRequest()
        var didComplete = false
        var didStart = false
        let task = request.start(operation: {
            didStart = true
            return image
        }, completion: { _ in didComplete = true })
        request.cancel()
        await task.value
        XCTAssertFalse(didStart)
        XCTAssertFalse(didComplete)
    }

    private func testImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

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
