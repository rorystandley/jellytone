import XCTest

@MainActor
final class BrowseDestinationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLibraryUsesBrowseDestinationsAndArtworkLedAlbumGrid() {
        var app = launch(["--ui-testing-library"])
        openTab("Library", in: app)

        XCTAssertTrue(app.buttons["library-playlists-link"].waitForExistence(timeout: 4))
        for identifier in [
            "library-artists-link",
            "library-albums-link",
            "library-tracks-link",
            "library-genres-link",
            "library-favourites-link",
            "library-downloads-link",
        ] {
            scrollUntilHittable(app.buttons[identifier], in: app)
            XCTAssertTrue(app.buttons[identifier].isHittable)
        }
        XCTAssertTrue(element("library-album-album-artwork", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["No artwork for 夜明け — A Deliberately Long Album Title"].exists)
        capture("library-compact-content", app: app)
        app.terminate()

        app = launch(["--ui-testing-library", "--ui-testing-library-empty"])
        openTab("Library", in: app)
        scrollUntilHittable(app.staticTexts["No albums found"], in: app)
        XCTAssertTrue(app.staticTexts["No albums found"].waitForExistence(timeout: 4))
    }

    func testSearchResultsOpenArtistAndAlbumDestinations() {
        var app = launch(["--ui-testing-search"])
        openTab("Search", in: app)
        enterSearch("aurora", in: app)

        let artist = element("search-artist-artist-unicode", in: app)
        let album = element("search-album-album-artwork", in: app)
        XCTAssertTrue(artist.waitForExistence(timeout: 5))
        XCTAssertTrue(album.exists)
        capture("search-results", app: app)

        artist.tap()
        XCTAssertTrue(app.navigationBars["Björk Guðmundsdóttir & The Synthetic Orchestra"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Top Songs"].waitForExistence(timeout: 4))
        let artistAlbum = element("artist-album-album-artwork", in: app)
        scrollUntilHittable(artistAlbum, in: app)
        XCTAssertTrue(artistAlbum.isHittable)
        capture("artist-detail", app: app)
        // Regression: an album tap must open the album, not re-push the artist.
        artistAlbum.tap()
        XCTAssertTrue(app.navigationBars["Aurora Lines"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["album-play-all"].waitForExistence(timeout: 4))
        app.terminate()

        app = launch(["--ui-testing-search"])
        openTab("Search", in: app)
        enterSearch("aurora", in: app)
        let artworkAlbum = element("search-album-album-artwork", in: app)
        XCTAssertTrue(artworkAlbum.waitForExistence(timeout: 5))
        artworkAlbum.tap()
        XCTAssertTrue(app.navigationBars["Aurora Lines"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Disc 2"].exists)
        scrollUntilHittable(app.buttons["album-play-all"], in: app)
        XCTAssertTrue(app.buttons["album-play-all"].isHittable)
        XCTAssertTrue(app.buttons["album-shuffle"].isHittable)
        capture("album-artwork-multidisc", app: app)

        let albumArtist = element("album-artist", in: app)
        XCTAssertTrue(albumArtist.waitForExistence(timeout: 4))
        albumArtist.tap()
        XCTAssertTrue(app.navigationBars["Björk Guðmundsdóttir"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Top Songs"].waitForExistence(timeout: 4))
        capture("album-artist-destination", app: app)
    }


    func testLibraryArtistAlbumTapOpensAlbumNotArtist() {
        let app = launch(["--ui-testing-library", "--ui-testing-artists", "--ui-testing-browse-details"])
        openTab("Library", in: app)

        let artistsLink = app.buttons["library-artists-link"]
        XCTAssertTrue(artistsLink.waitForExistence(timeout: 4))
        artistsLink.tap()

        let artistRow = element("artist-row-artist-artwork", in: app)
        XCTAssertTrue(artistRow.waitForExistence(timeout: 4))
        artistRow.tap()
        XCTAssertTrue(app.staticTexts["Top Songs"].waitForExistence(timeout: 4))

        let artistAlbum = element("artist-album-album-artwork", in: app)
        scrollUntilHittable(artistAlbum, in: app)
        XCTAssertTrue(artistAlbum.isHittable)
        // Regression: an album tap must open the album, not re-push the artist —
        // the Library stack registers the Album destination at its root and the
        // Artists list pushes artists by value.
        artistAlbum.tap()
        XCTAssertTrue(app.navigationBars["Aurora Lines"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["album-play-all"].waitForExistence(timeout: 4))
        capture("library-artist-album", app: app)
    }

    func testSearchIdleLoadingNoResultsAndErrorRemainActionable() {
        var app = launch(["--ui-testing-search"])
        openTab("Search", in: app)
        XCTAssertTrue(app.staticTexts["Search your music"].waitForExistence(timeout: 3))
        app.terminate()

        app = launch(["--ui-testing-search", "--ui-testing-search-loading"])
        openTab("Search", in: app)
        enterSearch("loading", in: app)
        XCTAssertTrue(app.staticTexts["Searching music"].waitForExistence(timeout: 4))
        app.terminate()

        app = launch(["--ui-testing-search", "--ui-testing-search-no-results"])
        openTab("Search", in: app)
        enterSearch("unknown", in: app)
        XCTAssertTrue(app.staticTexts["No results for “unknown”"].waitForExistence(timeout: 5))
        capture("search-no-results", app: app)
        app.terminate()

        app = launch(["--ui-testing-search", "--ui-testing-search-error"])
        openTab("Search", in: app)
        enterSearch("failure", in: app)
        XCTAssertTrue(app.staticTexts["Search unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try Again"].isHittable)
    }

    func testMissingArtworkAlbumKeepsLongMetadataAndPlaybackActionsReachable() {
        let app = launch(["--ui-testing-library"])
        openTab("Library", in: app)
        let album = element("library-album-album-missing", in: app)
        XCTAssertTrue(album.waitForExistence(timeout: 4))
        album.tap()
        XCTAssertTrue(app.navigationBars["夜明け — A Deliberately Long Album Title"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["No artwork for 夜明け — A Deliberately Long Album Title"].exists)
        scrollUntilHittable(app.buttons["album-play-all"], in: app)
        XCTAssertTrue(app.buttons["album-play-all"].isHittable)
        capture("album-missing-artwork", app: app)
    }

    func testAlbumArtistOpensArtistDestination() {
        let app = launch(["--ui-testing-library", "--ui-testing-browse-details"])
        openTab("Library", in: app)

        let album = element("library-album-album-artwork", in: app)
        XCTAssertTrue(album.waitForExistence(timeout: 4))
        album.tap()
        XCTAssertTrue(app.navigationBars["Aurora Lines"].waitForExistence(timeout: 4))

        let artist = element("album-artist", in: app)
        XCTAssertTrue(artist.waitForExistence(timeout: 4))
        artist.tap()
        XCTAssertTrue(app.navigationBars["Synthetic Artist"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Top Songs"].waitForExistence(timeout: 4))
        capture("album-artist-destination", app: app)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        return app
    }

    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 4))
        tab.tap()
    }

    private func enterSearch(_ query: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(query)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
