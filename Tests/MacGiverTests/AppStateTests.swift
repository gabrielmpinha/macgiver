import XCTest
@testable import MacGiver

@MainActor
final class AppStateTests: XCTestCase {
    func testMenuBarSymbolStartsInactive() {
        let state = BacklightStub().makeState()
        XCTAssertEqual(state.menuBarSymbolName, "bolt")
    }

    func testKeyboardLightInitialStateUsesHardwareBrightness() {
        XCTAssertEqual(BacklightStub(brightness: 0.2).makeState().keyboardLightEnabled, true)
        XCTAssertEqual(BacklightStub(brightness: 0).makeState().keyboardLightEnabled, false)
        let unavailable = BacklightStub(brightness: nil).makeState()
        XCTAssertNil(unavailable.keyboardLightEnabled)
        XCTAssertNotNil(unavailable.keyboardLightMessage)
    }

    func testKeyboardLightRestoresFractionalBrightness() async {
        let hardware = BacklightStub(brightness: 0.1963678)
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(false)
        XCTAssertEqual(state.keyboardLightEnabled, false)
        XCTAssertEqual(hardware.brightness, 0)
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(state.keyboardLightEnabled, true)
        XCTAssertEqual(hardware.brightness, 0.1963678)
        XCTAssertNil(state.keyboardLightMessage)
    }

    func testInitiallyDarkKeyboardCanBeTurnedOn() async {
        let hardware = BacklightStub(brightness: 0)
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(state.keyboardLightEnabled, true)
        XCTAssertEqual(hardware.brightness, 0.5)
    }

    func testRepeatedOffDoesNotLoseSavedBrightness() async {
        let hardware = BacklightStub(brightness: 0.37)
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(false)
        await state.setKeyboardLightEnabled(false)
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(hardware.writes, [0, 0.37])
        XCTAssertEqual(hardware.brightness, 0.37)
    }

    func testOnWhileAlreadyOnDoesNotOverrideExternalBrightness() async {
        let hardware = BacklightStub(brightness: 0.23)
        let state = hardware.makeState()
        hardware.brightness = 0.72
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(hardware.brightness, 0.72)
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    func testOffUsesFreshReadingAfterExternalChange() async {
        let hardware = BacklightStub(brightness: 0.23)
        let state = hardware.makeState()
        hardware.brightness = 0.72
        await state.setKeyboardLightEnabled(false)
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(hardware.brightness, 0.72)
    }

    func testFailedOffReportsObservedState() async {
        let hardware = BacklightStub(brightness: 0.3)
        hardware.writeAccepted = false
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(false)
        XCTAssertEqual(state.keyboardLightEnabled, true)
        XCTAssertEqual(hardware.brightness, 0.3)
        XCTAssertNotNil(state.keyboardLightMessage)
        XCTAssertFalse(state.keyboardLightChanging)
    }

    func testFailedOnRetainsBrightnessForRetry() async {
        let hardware = BacklightStub(brightness: 0.37)
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(false)
        hardware.writeAccepted = false
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(state.keyboardLightEnabled, false)
        XCTAssertNotNil(state.keyboardLightMessage)
        hardware.writeAccepted = true
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(hardware.brightness, 0.37)
        XCTAssertNil(state.keyboardLightMessage)
    }

    func testAcceptedWriteWithoutEffectIsNotSuccess() async {
        let hardware = BacklightStub(brightness: 0.3)
        hardware.applyWrite = false
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(false)
        XCTAssertEqual(state.keyboardLightEnabled, true)
        XCTAssertNotNil(state.keyboardLightMessage)
    }

    func testFailedWriteThatChangedHardwareRefreshesState() async {
        let hardware = BacklightStub(brightness: 0.4)
        let state = AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: { hardware.brightness },
            writeBrightness: { value in
                hardware.brightness = value
                return false
            }
        ))
        await state.setKeyboardLightEnabled(false)
        XCTAssertEqual(state.keyboardLightEnabled, false)
        XCTAssertNotNil(state.keyboardLightMessage)
    }

    func testUnconfirmedOffPreservesRestoreValue() async {
        let hardware = BacklightStub(brightness: 0.42)
        var readingAvailable = true
        let state = AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: { readingAvailable ? hardware.brightness : nil },
            writeBrightness: { value in
                hardware.brightness = value
                readingAvailable = value > 0
                return true
            }
        ))
        await state.setKeyboardLightEnabled(false)
        XCTAssertNil(state.keyboardLightEnabled)
        XCTAssertNotNil(state.keyboardLightMessage)
        readingAvailable = true
        await state.setKeyboardLightEnabled(true)
        XCTAssertEqual(hardware.brightness, 0.42)
        XCTAssertEqual(state.keyboardLightEnabled, true)
    }

    func testUnavailableReadingDoesNotWriteAndCanRecover() async {
        let hardware = BacklightStub(brightness: nil)
        let state = hardware.makeState()
        await state.setKeyboardLightEnabled(false)
        XCTAssertTrue(hardware.writes.isEmpty)
        XCTAssertNil(state.keyboardLightEnabled)
        hardware.brightness = 0.4
        state.retryKeyboardLight()
        XCTAssertEqual(state.keyboardLightEnabled, true)
        XCTAssertNil(state.keyboardLightMessage)
    }

    func testRefreshReflectsExternalChanges() {
        let hardware = BacklightStub(brightness: 0.4)
        let state = hardware.makeState()
        hardware.brightness = 0
        state.refreshKeyboardLight()
        XCTAssertEqual(state.keyboardLightEnabled, false)
        hardware.brightness = 0.2
        state.refreshKeyboardLight()
        XCTAssertEqual(state.keyboardLightEnabled, true)
    }

    func testReadFailureAfterVerifiedWriteKeepsRetryMessage() async {
        var brightness = 0.4
        var readsAfterWrite = 0
        var hasWritten = false
        let state = AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: {
                if hasWritten { readsAfterWrite += 1 }
                return readsAfterWrite > 1 ? nil : brightness
            },
            writeBrightness: { value in
                brightness = value
                hasWritten = true
                return true
            }
        ))
        await state.setKeyboardLightEnabled(false)
        XCTAssertNil(state.keyboardLightEnabled)
        XCTAssertNotNil(state.keyboardLightMessage)
        XCTAssertFalse(state.keyboardLightChanging)
    }

    func testRefreshClearsRecoveredReadError() {
        let hardware = BacklightStub(brightness: nil)
        let state = hardware.makeState()
        XCTAssertNotNil(state.keyboardLightMessage)
        hardware.brightness = 0.2
        state.refreshKeyboardLight()
        XCTAssertEqual(state.keyboardLightEnabled, true)
        XCTAssertNil(state.keyboardLightMessage)
    }

    func testInvalidBrightnessIsUnknownAndNeverWritten() async {
        for value in [-1, 1.01, Double.nan, Double.infinity] {
            let hardware = BacklightStub(brightness: value)
            let state = hardware.makeState()
            XCTAssertNil(state.keyboardLightEnabled)
            await state.setKeyboardLightEnabled(false)
            XCTAssertTrue(hardware.writes.isEmpty)
            XCTAssertNotNil(state.keyboardLightMessage)
        }
    }
}

@MainActor
private final class BacklightStub {
    var brightness: Double?
    var writeAccepted = true
    var applyWrite = true
    var writes: [Double] = []

    init(brightness: Double? = 0.3) {
        self.brightness = brightness
    }

    func makeState() -> AppState {
        AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: { self.brightness },
            writeBrightness: { value in
                self.writes.append(value)
                guard self.writeAccepted else { return false }
                if self.applyWrite { self.brightness = value }
                return true
            }
        ))
    }
}
