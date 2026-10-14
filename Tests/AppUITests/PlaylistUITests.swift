import XCTest

@MainActor
final class PlaylistUITests: XCTestCase {
    override func setUp() async throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testPlaylistFixtureSupportsBrowsingAndPlaybackActions() {
        let app = launchPlaylists(extraArguments: [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ])

        openPlaylists(in: app)

        let playlistRow = element(in: app, identifier: "playlist-row-playlist-road")
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 3))
        XCTAssertTrue(playlistRow.label.contains("Road Mix"))
        XCTAssertTrue(playlistRow.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)["No artwork for Road Mix 🎧"].exists,
            "The missing-artwork fixture must expose a meaningful fallback label"
        )
        playlistRow.tap()

        XCTAssertTrue(element(in: app, identifier: "playlist-detail-screen").waitForExistence(timeout: 3))

        let playAll = app.buttons["playlist-play-all"]
        XCTAssertTrue(playAll.waitForExistence(timeout: 2))
        XCTAssertEqual(playAll.label, "Play All")
        XCTAssertTrue(playAll.isEnabled)
        XCTAssertTrue(playAll.isHittable)

        let shuffle = app.buttons["playlist-shuffle"]
        XCTAssertTrue(shuffle.exists)
        XCTAssertEqual(shuffle.label, "Shuffle")
        XCTAssertTrue(shuffle.isEnabled)
        XCTAssertTrue(shuffle.isHittable)

        let track = element(in: app, identifier: "playlist-track-occurrence-1")
        XCTAssertTrue(track.waitForExistence(timeout: 2))
        XCTAssertFalse(track.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(track.isHittable)
        capture("playlist-detail-duplicates", app: app)
    }

    func testPlaylistNavigationRemainsReachableInPortraitAndLandscape() {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = launchPlaylists()

            openPlaylists(in: app)

            let playlistRow = element(in: app, identifier: "playlist-row-playlist-road")
            XCTAssertTrue(playlistRow.waitForExistence(timeout: 3), "Playlist row was unavailable in \(orientation)")
            XCTAssertTrue(playlistRow.isHittable, "Playlist row was clipped in \(orientation)")
            app.terminate()
        }
    }

    func testEmptyPlaylistFixtureHasAnAccessibleEmptyState() {
        let app = launchPlaylists(extraArguments: ["--ui-testing-playlists-empty"])

        openPlaylists(in: app)

        XCTAssertTrue(app.staticTexts["No playlists found"].waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(in: app, identifierPrefix: "playlist-row-").exists)
        assertNoPrivateConnectionData(in: app)
    }

    func testEmptyAndNonPlayablePlaylistDetailsAreHonest() {
        var app = launchPlaylists()
        openPlaylists(in: app)

        element(in: app, identifier: "playlist-row-playlist-empty").tap()
        XCTAssertTrue(app.staticTexts["Empty playlist"].waitForExistence(timeout: 3))
        app.terminate()

        app = launchPlaylists()
        openPlaylists(in: app)
        let unsupported = element(in: app, identifier: "playlist-row-playlist-nonplayable")
        XCTAssertTrue(unsupported.waitForExistence(timeout: 3))
        unsupported.tap()
        XCTAssertTrue(app.staticTexts["No playable audio"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["playlist-play-all"].exists)
        XCTAssertFalse(app.buttons["playlist-shuffle"].exists)
    }

    func testPlaylistLayoutSupportsDarkAppearanceAndLargeDynamicType() {
        let app = launchPlaylists(extraArguments: [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])

        openPlaylists(in: app)
        let playlistRow = element(in: app, identifier: "playlist-row-playlist-road")
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 3))
        XCTAssertTrue(playlistRow.isHittable)
        playlistRow.tap()
        XCTAssertTrue(app.buttons["playlist-play-all"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["playlist-shuffle"].isHittable)
        XCTAssertTrue(element(in: app, identifier: "playlist-track-occurrence-1").isHittable)
        XCTAssertFalse(app.buttons["Rename playlist"].exists)
        XCTAssertFalse(app.buttons["Rename"].exists)
    }

    func testPlaylistErrorIsActionableAndDoesNotExposeConnectionData() {
        let app = launchPlaylists(extraArguments: ["--ui-testing-playlists-error"])

        openPlaylists(in: app)

        XCTAssertTrue(app.staticTexts["Couldn’t load playlists"].waitForExistence(timeout: 3))
        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(retry.isHittable)
        assertNoPrivateConnectionData(in: app)
    }

    func testPlaylistHierarchyDoesNotExposeConnectionData() {
        let app = launchPlaylists()

        openPlaylists(in: app)
        assertNoPrivateConnectionData(in: app)

        let playlistRow = element(in: app, identifier: "playlist-row-playlist-road")
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 3))
        playlistRow.tap()
        XCTAssertTrue(element(in: app, identifier: "playlist-detail-screen").waitForExistence(timeout: 3))
        assertNoPrivateConnectionData(in: app)
    }

    private func launchPlaylists(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-playlists"] + extraArguments
        app.launch()
        return app
    }

    private func openPlaylists(in app: XCUIApplication) {
        let libraryDestination = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Library")
        ).firstMatch
        XCTAssertTrue(libraryDestination.waitForExistence(timeout: 5))
        libraryDestination.tap()

        let playlistsLink = app.buttons["library-playlists-link"]
        XCTAssertTrue(playlistsLink.waitForExistence(timeout: 3))
        XCTAssertFalse(playlistsLink.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(playlistsLink.isHittable)
        playlistsLink.tap()

        XCTAssertTrue(element(in: app, identifier: "playlists-screen").waitForExistence(timeout: 3))
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func firstElement(in app: XCUIApplication, identifierPrefix: String) -> XCUIElement {
        let elements = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        )
        return elements.firstMatch
    }

    private func assertNoPrivateConnectionData(in app: XCUIApplication) {
        let hierarchy = app.debugDescription.lowercased()
        for forbiddenValue in [
            "://",
            "x-emby-token",
            "authorization:",
            "bearer ",
            "access_token",
            "synthetic-password",
        ] {
            XCTAssertFalse(
                hierarchy.contains(forbiddenValue),
                "Playlist accessibility hierarchy exposed forbidden connection data: \(forbiddenValue)"
            )
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
