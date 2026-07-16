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

    func testHTTPRequiresExplicitTailscaleConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let server = app.textFields["https://jellyfin.example.com"]
        server.tap()
        server.typeText("http://music.example.ts.net:8096")
        app.textFields["Username"].tap()
        app.textFields["Username"].typeText("listener")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("synthetic-password")
        app.buttons["Connect"].tap()

        XCTAssertTrue(app.alerts["HTTP is not encrypted"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Connect over Tailscale"].exists)
    }
}
