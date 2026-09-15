import XCTest
@testable import MacGiver

final class AppStateTests: XCTestCase {
    @MainActor
    func testMenuBarSymbolStartsInactive() {
        let state = AppState()
        XCTAssertEqual(state.menuBarSymbolName, "bolt")
    }

    @MainActor
    func testKeyboardLightToggleRestoresPreviousBrightness() {
        var brightness = 96
        let controller = KeyboardBacklightController(
            readBrightness: { brightness },
            writeBrightness: { value in
                brightness = value
                return true
            }
        )
        let state = AppState(keyboardBacklightController: controller)

        state.toggleKeyboardLight()
        XCTAssertFalse(state.keyboardLightEnabled)
        XCTAssertEqual(brightness, 0)

        state.toggleKeyboardLight()
        XCTAssertTrue(state.keyboardLightEnabled)
        XCTAssertEqual(brightness, 96)
        XCTAssertNil(state.keyboardLightMessage)
    }

    @MainActor
    func testKeyboardLightToggleKeepsStateWhenWriteFails() {
        let controller = KeyboardBacklightController(
            readBrightness: { 96 },
            writeBrightness: { _ in false }
        )
        let state = AppState(keyboardBacklightController: controller)

        state.toggleKeyboardLight()

        XCTAssertTrue(state.keyboardLightEnabled)
        XCTAssertNotNil(state.keyboardLightMessage)
    }
}
