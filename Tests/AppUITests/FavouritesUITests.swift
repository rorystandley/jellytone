import XCTest

@MainActor
final class FavouritesUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testFavouriteFixtureSupportsAccessibleBrowsingNavigationAndPlaybackActions() {
        let app = launchFavourites(extraArguments: [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ])
        openFavourites(in: app)

        let artist = element(in: app, identifier: "favourites-artist-artist-favourite")
        XCTAssertTrue(artist.waitForExistence(timeout: 3))
        XCTAssertTrue(artist.isHittable)
        XCTAssertTrue(artist.label.contains("Favourite Artist"))
        capture("favourites-populated", app: app)

        let album = element(in: app, identifier: "favourites-album-album-favourite")
        XCTAssertTrue(album.waitForExistence(timeout: 3))
        XCTAssertTrue(album.isHittable)
        XCTAssertTrue(album.label.contains("Favourite Album"))
        XCTAssertTrue(app.descendants(matching: .any)["No artwork for Favourite Album"].exists)

        assertAction(app.buttons["favourites-play-all"], label: "Play All")
        assertAction(app.buttons["favourites-shuffle"], label: "Shuffle")

        let duplicateOccurrence = element(in: app, identifier: "favourites-track-favourite-occurrence-3")
        for _ in 0..<4 where !duplicateOccurrence.exists { app.swipeUp() }
        XCTAssertTrue(duplicateOccurrence.waitForExistence(timeout: 2))
        XCTAssertTrue(duplicateOccurrence.isHittable)
        XCTAssertFalse(duplicateOccurrence.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        assertNoPrivateConnectionData(in: app)
    }

    func testFavouriteArtistAndAlbumOpenExistingLibraryDestinations() {
        var app = launchFavourites()
        openFavourites(in: app)
        element(in: app, identifier: "favourites-artist-artist-favourite").tap()
        XCTAssertTrue(app.navigationBars["Favourite Artist"].waitForExistence(timeout: 3))
        app.terminate()

        app = launchFavourites()
        openFavourites(in: app)
        element(in: app, identifier: "favourites-album-album-favourite").tap()
        XCTAssertTrue(app.navigationBars["Favourite Album"].waitForExistence(timeout: 3))
    }

    func testFavouriteArtistAlbumTapOpensAlbumNotArtist() {
        let app = launchFavourites(extraArguments: ["--ui-testing-browse-details"])
        openFavourites(in: app)

        element(in: app, identifier: "favourites-artist-artist-favourite").tap()
        XCTAssertTrue(app.navigationBars["Favourite Artist"].waitForExistence(timeout: 3))

        let artistAlbum = element(in: app, identifier: "artist-album-album-artwork")
        for _ in 0..<6 where !artistAlbum.isHittable { app.swipeUp() }
        XCTAssertTrue(artistAlbum.isHittable)
        // Regression: opening an album from a favourite artist must not re-push
        // the artist — the favourite-artist link is value-based so it no longer
        // re-fires when the album pushes onto the Library stack.
        artistAlbum.tap()
        XCTAssertTrue(app.navigationBars["Aurora Lines"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["album-play-all"].waitForExistence(timeout: 4))
        capture("favourites-artist-album", app: app)
    }

    func testFavouriteLayoutSupportsCompactAndRegularWidthConventions() {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = launchFavourites()
            openFavourites(in: app)

            let artist = element(in: app, identifier: "favourites-artist-artist-favourite")
            XCTAssertTrue(artist.waitForExistence(timeout: 3), "Favourite artist unavailable in \(orientation)")
            XCTAssertTrue(artist.isHittable, "Favourite artist clipped in \(orientation)")
            XCTAssertTrue(app.buttons["favourites-play-all"].isHittable)
            XCTAssertTrue(app.buttons["favourites-shuffle"].isHittable)
            app.terminate()
        }
    }

    func testFavouriteLayoutSupportsDarkAppearanceLargeDynamicTypeAndReduceMotion() {
        let app = launchFavourites(extraArguments: [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled", "YES",
        ])
        openFavourites(in: app)

        XCTAssertTrue(element(in: app, identifier: "favourites-artist-artist-favourite").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["favourites-play-all"].isHittable)
        XCTAssertTrue(app.buttons["favourites-shuffle"].isHittable)
        let firstTrack = element(in: app, identifier: "favourites-track-favourite-occurrence-1")
        scrollUntilHittable(firstTrack, in: app)
        XCTAssertTrue(firstTrack.isHittable)
        XCTAssertFalse(app.buttons["Unfavourite Repeated Favourite"].exists)
    }

    func testFavouriteLoadingAndEmptyStatesAreAccessible() {
        var app = launchFavourites(extraArguments: ["--ui-testing-favourites-loading"])
        openFavourites(in: app)
        XCTAssertTrue(app.staticTexts["Loading favourite artists…"].waitForExistence(timeout: 8))
        assertNoPrivateConnectionData(in: app)
        app.terminate()

        app = launchFavourites(extraArguments: ["--ui-testing-favourites-empty"])
        openFavourites(in: app)
        XCTAssertTrue(app.staticTexts["No favourites found"].waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(in: app, identifierPrefix: "favourites-artist-").exists)
        XCTAssertFalse(firstElement(in: app, identifierPrefix: "favourites-album-").exists)
        XCTAssertFalse(firstElement(in: app, identifierPrefix: "favourites-track-").exists)
        capture("favourites-empty", app: app)
        assertNoPrivateConnectionData(in: app)
    }

    func testFavouriteInitialFailureIsRetryableAndPrivate() {
        let app = launchFavourites(extraArguments: ["--ui-testing-favourites-error"])
        openFavourites(in: app)

        XCTAssertTrue(app.staticTexts["Couldn’t load favourites"].waitForExistence(timeout: 8))
        assertAction(app.buttons["Try Again"], label: "Try Again")
        assertNoPrivateConnectionData(in: app)
    }

    func testFavouritePaginationFailurePreservesLoadedContentAndOffersRetry() {
        let app = launchFavourites(extraArguments: ["--ui-testing-favourites-pagination-error"])
        openFavourites(in: app)

        XCTAssertTrue(element(in: app, identifier: "favourites-artist-artist-favourite").waitForExistence(timeout: 3))
        let retry = app.buttons["favourites-retry-more-tracks"]
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertEqual(retry.label, "Retry More Tracks")
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(retry.isHittable)
        assertNoPrivateConnectionData(in: app)
    }

    private func launchFavourites(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-favourites"] + extraArguments
        app.launch()
        return app
    }

    private func openFavourites(in app: XCUIApplication) {
        let libraryDestination = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Library")
        ).firstMatch
        XCTAssertTrue(libraryDestination.waitForExistence(timeout: 5))
        libraryDestination.tap()

        let favouritesLink = app.buttons["library-favourites-link"]
        XCTAssertTrue(favouritesLink.waitForExistence(timeout: 3))
        XCTAssertTrue(favouritesLink.isHittable)
        favouritesLink.tap()
        XCTAssertTrue(element(in: app, identifier: "favourites-screen").waitForExistence(timeout: 3))
    }

    private func assertAction(_ element: XCUIElement, label: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        XCTAssertEqual(element.label, label)
        XCTAssertTrue(element.isEnabled)
        XCTAssertTrue(element.isHittable)
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func firstElement(in app: XCUIApplication, identifierPrefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        ).firstMatch
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
    }

    private func assertNoPrivateConnectionData(in app: XCUIApplication) {
        let hierarchy = app.debugDescription.lowercased()
        for forbiddenValue in [
            "://",
            "x-emby-token",
            "authorization:",
            "bearer ",
            "access_token",
            "synthetic-token",
            "synthetic-user",
        ] {
            XCTAssertFalse(
                hierarchy.contains(forbiddenValue),
                "Favourites accessibility hierarchy exposed forbidden connection data: \(forbiddenValue)"
            )
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
