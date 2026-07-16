import XCTest

final class ConnectionScreenUITests: XCTestCase {
    func testColdLaunchShowsConnectionForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Jellyfin Audio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["https://jellyfin.example.com"].exists)
        XCTAssertTrue(app.buttons["Connect"].exists)
    }
}
