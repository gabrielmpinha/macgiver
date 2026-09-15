import XCTest
@testable import MacGiver

final class AppStateTests: XCTestCase {
    @MainActor
    func testMenuBarSymbolStartsInactive() {
        let state = AppState()
        XCTAssertEqual(state.menuBarSymbolName, "bolt")
    }
}
