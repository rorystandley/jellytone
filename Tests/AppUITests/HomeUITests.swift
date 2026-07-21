import XCTest

@MainActor
final class HomeUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testHomeRecentShelvesSupportAccessibleAlbumAndTrackActions() {
        let app = launchHome()
        XCTAssertTrue(element(in: app, identifier: "home-screen").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Recently Added"].exists)
        XCTAssertTrue(app.staticTexts["Recently Played"].exists)

        let album = element(in: app, identifier: "home-recently-added-album-home-album-new")
        XCTAssertTrue(album.waitForExistence(timeout: 3))
        XCTAssertTrue(album.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["No artwork for New Album"].exists)
        album.tap()
        XCTAssertTrue(app.navigationBars["New Album"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        let track = element(in: app, identifier: "home-recently-played-track-home-track-1")
        XCTAssertTrue(track.waitForExistence(timeout: 3))
        XCTAssertTrue(track.isHittable)
        XCTAssertFalse(track.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        XCTAssertTrue(app.staticTexts["Favourite Artists"].exists)
        let artist = element(in: app, identifier: "home-favourite-artist-home-artist-1")
        XCTAssertTrue(artist.waitForExistence(timeout: 3))
        XCTAssertTrue(artist.isHittable)
        artist.tap()
        XCTAssertTrue(app.navigationBars["Synthetic Artist"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        capture("home-light-content", app: app)
        assertNoPrivateConnectionData(in: app)
    }

    func testHomeSupportsCompactRegularDarkLargeTypeAndReduceMotion() {
        let configurations: [[String]] = [
            [],
            ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge", "-UIAccessibilityReduceMotionEnabled", "YES"],
        ]
        for arguments in configurations {
            let app = launchHome(extraArguments: arguments)
            let album = element(in: app, identifier: "home-recently-added-album-home-album-new")
            XCTAssertTrue(album.waitForExistence(timeout: 4))
            XCTAssertTrue(album.isHittable)
            if !arguments.isEmpty { capture("home-dark-missing-artwork-large-type", app: app) }
            app.terminate()
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        let regularApp = launchHome()
        let landscapeAlbum = element(in: regularApp, identifier: "home-recently-added-album-home-album-new")
        XCTAssertTrue(landscapeAlbum.waitForExistence(timeout: 4))
        XCTAssertTrue(landscapeAlbum.isHittable)
    }

    func testHomeLoadingEmptyFailureAndRetryAreHonestAndPrivate() {
        var app = launchHome(extraArguments: ["--ui-testing-home-loading"])
        XCTAssertTrue(element(in: app, identifier: "home-loading-skeleton").waitForExistence(timeout: 3))
        assertNoPrivateConnectionData(in: app)
        app.terminate()

        app = launchHome(extraArguments: ["--ui-testing-home-empty"])
        XCTAssertTrue(app.staticTexts["Nothing recent yet"].waitForExistence(timeout: 3))
        assertNoPrivateConnectionData(in: app)
        app.terminate()

        app = launchHome(extraArguments: ["--ui-testing-home-error"])
        XCTAssertTrue(app.staticTexts["Couldn’t load Home"].waitForExistence(timeout: 3))
        let retry = app.buttons["home-retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isHittable)
        assertNoPrivateConnectionData(in: app)
    }

    func testCachedRefreshKeepsShelfReachableAndPartialFailureIsVisible() {
        let app = launchHome(extraArguments: ["--ui-testing-home-cached-partial-error"])
        let album = element(in: app, identifier: "home-recently-added-album-home-album-cached")
        XCTAssertTrue(album.waitForExistence(timeout: 3))
        // Background refresh is deliberately silent — no status chip may
        // appear over the cached shelves while it runs.
        XCTAssertFalse(element(in: app, identifier: "home-refreshing").exists)
        XCTAssertTrue(app.staticTexts["Recently Played"].exists)
        XCTAssertTrue(element(in: app, identifier: "home-partial-failure").exists)
        assertNoPrivateConnectionData(in: app)
    }

    func testAvatarOpensSettingsWithSignOutAndCachePurge() {
        let app = launchHome()
        let avatar = element(in: app, identifier: "home-settings")
        XCTAssertTrue(avatar.waitForExistence(timeout: 4))
        avatar.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings-sign-out"].exists)
        let clear = app.buttons["settings-clear-image-cache"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertTrue(app.staticTexts["Zero KB"].waitForExistence(timeout: 3))
        assertNoPrivateConnectionData(in: app)
    }

    func testAppearanceChoicePersistsAcrossAppLaunches() {
        var app = launchHome()
        openSettings(in: app)
        app.buttons["settings-appearance"].tap()
        let dark = app.buttons["settings-appearance-option-dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 3))
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        app.terminate()

        app = launchHome()
        openSettings(in: app)
        app.buttons["settings-appearance"].tap()
        let restoredAppearance = app.buttons["settings-appearance-option-dark"]
        XCTAssertTrue(restoredAppearance.isSelected)

        // Keep later UI tests independent of this test's persisted choice.
        app.buttons["settings-appearance-option-system"].tap()
    }

    func testContinueListeningUsesTheExistingPlaybackController() {
        let app = launchHome(extraArguments: ["--ui-testing-restored-playback"])
        let card = element(in: app, identifier: "home-continue-listening")
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(card.label.contains("Continue listening"))
        assertNoPrivateConnectionData(in: app)
    }

    private func launchHome(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home"] + extraArguments
        app.launch()
        return app
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func openSettings(in app: XCUIApplication) {
        let avatar = element(in: app, identifier: "home-settings")
        XCTAssertTrue(avatar.waitForExistence(timeout: 4))
        avatar.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    }

    private func assertNoPrivateConnectionData(in app: XCUIApplication) {
        let hierarchy = app.debugDescription.lowercased()
        for forbiddenValue in ["://", "x-emby-token", "authorization:", "bearer ", "access_token", "synthetic-token", "synthetic-user"] {
            XCTAssertFalse(hierarchy.contains(forbiddenValue), "Home accessibility hierarchy exposed forbidden connection data: \(forbiddenValue)")
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
