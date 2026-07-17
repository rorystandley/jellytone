import XCTest

final class ConnectionScreenUITests: XCTestCase {
    func testMiniPlayerKeepsEveryPrimaryTabReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Home"].exists)
        XCTAssertTrue(tabBar.buttons["Library"].exists)
        XCTAssertTrue(tabBar.buttons["Search"].exists)
        XCTAssertTrue(app.staticTexts["Visible Mini Player"].exists)

        tabBar.buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Search your music"].exists)
        XCTAssertTrue(tabBar.buttons["Home"].exists)
        XCTAssertTrue(tabBar.buttons["Library"].exists)
        XCTAssertTrue(tabBar.buttons["Search"].isSelected)
    }

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
