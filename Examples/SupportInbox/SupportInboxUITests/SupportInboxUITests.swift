import XCTest

final class SupportInboxUITests: XCTestCase {
    @MainActor
    func testMissingKeyNeverMakesALiveRequest() {
        let app = XCUIApplication()
        app.launchEnvironment["TYPESAFE_API_KEY"] = ""
        app.launch()
        let analyze = app.buttons["analyze-ticket"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        XCTAssertFalse(analyze.isEnabled)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["API key missing"].waitForExistence(timeout: 5))
    }
}
