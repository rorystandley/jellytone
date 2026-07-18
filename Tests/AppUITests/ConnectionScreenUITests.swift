import XCTest

@MainActor
final class ConnectionScreenUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCUIDevice.shared.orientation = .portrait
    }

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

    func testQueueProtectsCurrentTrackAndClearUpNextKeepsItVisible() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell"]
        app.launch()

        app.buttons["mini-player-details"].tap()
        XCTAssertTrue(app.navigationBars["Now Playing"].waitForExistence(timeout: 3))
        app.buttons["show-queue"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Visible Mini Player"].exists)
        XCTAssertTrue(app.buttons["Play First Up Next by Synthetic Artist"].exists)
        XCTAssertTrue(app.buttons["Play Second Up Next by Synthetic Artist"].exists)

        app.buttons["Clear Up Next"].tap()
        XCTAssertTrue(app.staticTexts["Visible Mini Player"].exists)
        XCTAssertTrue(app.staticTexts["Nothing Up Next"].exists)
        XCTAssertFalse(app.buttons["Clear Up Next"].exists)
    }

    func testRestoredPlaybackPositionDrivesNowPlayingPresentation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell", "--ui-testing-restored-playback"]
        app.launch()

        app.buttons["mini-player-details"].tap()
        XCTAssertTrue(app.navigationBars["Now Playing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1:13"].exists)
        XCTAssertTrue(app.staticTexts["−1:47"].exists)
        XCTAssertTrue(app.buttons["Play"].exists)
    }

    func testPlayerFixturesExposeArtworkPlaybackAndAccessibleControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell", "--ui-testing-player-artwork", "--ui-testing-player-playing"]
        app.launch()

        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["mini-player-details"].tap()
        XCTAssertTrue(app.navigationBars["Now Playing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Pause"].exists)
        XCTAssertEqual(app.buttons["Enable shuffle"].value as? String, "Off")
        XCTAssertTrue(app.buttons["show-queue"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "now-playing-artwork"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPlayerLongMetadataAndPreparingStateKeepControlsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell", "--ui-testing-player-long-unicode", "--ui-testing-player-preparing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["夜明けの街で聴く A deliberately very long song title that should remain readable"].waitForExistence(timeout: 3))
        app.buttons["mini-player-details"].tap()
        XCTAssertTrue(app.staticTexts["Preparing playback"].waitForExistence(timeout: 3))
        for _ in 0..<3 where !app.buttons["show-queue"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["show-queue"].isHittable)
    }

    func testPlaybackFailureIsActionableAndDoesNotHideShell() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell", "--ui-testing-player-failure"]
        app.launch()

        XCTAssertTrue(app.alerts["Something went wrong"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Playback could not continue. Try another track."].exists)
        app.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["mini-player-details"].exists)
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
