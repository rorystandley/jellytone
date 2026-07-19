import XCTest

@MainActor
final class GenreUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testGenreFixtureSupportsAccessibleBrowsingAndPlaybackActions() {
        let app = launchGenres()
        openGenres(in: app)

        let genreRow = element(in: app, identifier: "genre-row-genre-rock")
        XCTAssertTrue(genreRow.waitForExistence(timeout: 3))
        XCTAssertTrue(genreRow.label.contains("Rock"))
        XCTAssertTrue(genreRow.isHittable)
        genreRow.tap()

        XCTAssertTrue(element(in: app, identifier: "genre-detail-screen").waitForExistence(timeout: 3))
        assertAction(app.buttons["genre-play-all"], label: "Play All")
        assertAction(app.buttons["genre-shuffle"], label: "Shuffle")

        let duplicateOccurrence = element(in: app, identifier: "genre-track-genre-occurrence-3")
        for _ in 0..<4 where !duplicateOccurrence.exists { app.swipeUp() }
        XCTAssertTrue(duplicateOccurrence.waitForExistence(timeout: 2))
        XCTAssertFalse(duplicateOccurrence.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(duplicateOccurrence.isHittable)
        capture("genre-detail-duplicates", app: app)
        assertNoPrivateConnectionData(in: app)
    }

    func testGenreLayoutSupportsCompactAndRegularWidthConventions() {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = launchGenres()
            openGenres(in: app)

            let genreRow = element(in: app, identifier: "genre-row-genre-rock")
            XCTAssertTrue(genreRow.waitForExistence(timeout: 3), "Genre row unavailable in \(orientation)")
            XCTAssertTrue(genreRow.isHittable, "Genre row clipped in \(orientation)")
            genreRow.tap()
            XCTAssertTrue(app.buttons["genre-play-all"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["genre-shuffle"].isHittable)
            app.terminate()
        }
    }

    func testGenreLayoutSupportsDarkAppearanceLargeDynamicTypeAndReduceMotion() {
        let app = launchGenres(extraArguments: [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled", "YES",
        ])
        openGenres(in: app)

        let genreRow = element(in: app, identifier: "genre-row-genre-rock")
        XCTAssertTrue(genreRow.waitForExistence(timeout: 3))
        XCTAssertTrue(genreRow.isHittable)
        genreRow.tap()
        XCTAssertTrue(app.buttons["genre-play-all"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["genre-shuffle"].isHittable)
        XCTAssertTrue(element(in: app, identifier: "genre-track-genre-occurrence-1").isHittable)
    }

    func testGenreLoadingStateIsAccessible() {
        let app = launchGenres(extraArguments: ["--ui-testing-genres-loading"])
        openGenres(in: app)

        XCTAssertTrue(app.staticTexts["Loading genres"].waitForExistence(timeout: 3))
        assertNoPrivateConnectionData(in: app)
    }

    func testEmptyGenreLibraryHasAnAccessibleEmptyState() {
        let app = launchGenres(extraArguments: ["--ui-testing-genres-empty"])
        openGenres(in: app)

        XCTAssertTrue(app.staticTexts["No genres found"].waitForExistence(timeout: 3))
        XCTAssertFalse(firstElement(in: app, identifierPrefix: "genre-row-").exists)
        assertNoPrivateConnectionData(in: app)
    }

    func testEmptyAndNonPlayableGenreDetailsAreHonest() {
        var app = launchGenres()
        openGenres(in: app)
        element(in: app, identifier: "genre-row-genre-empty").tap()
        XCTAssertTrue(app.staticTexts["Empty genre"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["genre-play-all"].exists)
        XCTAssertFalse(app.buttons["genre-shuffle"].exists)
        app.terminate()

        app = launchGenres()
        openGenres(in: app)
        element(in: app, identifier: "genre-row-genre-nonplayable").tap()
        XCTAssertTrue(app.staticTexts["No playable audio"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["genre-play-all"].exists)
        XCTAssertFalse(app.buttons["genre-shuffle"].exists)
    }

    func testGenreErrorIsRetryableAndPrivate() {
        let app = launchGenres(extraArguments: ["--ui-testing-genres-error"])
        openGenres(in: app)

        XCTAssertTrue(app.staticTexts["Couldn’t load genres"].waitForExistence(timeout: 3))
        assertAction(app.buttons["Try Again"], label: "Try Again")
        assertNoPrivateConnectionData(in: app)
    }

    func testGenrePaginationFailurePreservesLoadedContentAndOffersRetry() {
        let app = launchGenres(extraArguments: ["--ui-testing-genres-pagination-error"])
        openGenres(in: app)

        XCTAssertTrue(element(in: app, identifier: "genre-row-genre-rock").waitForExistence(timeout: 3))
        let retry = app.buttons["genre-load-more"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertEqual(retry.label, "Retry loading more genres")
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(retry.isHittable)
        assertNoPrivateConnectionData(in: app)
    }

    private func launchGenres(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-genres"] + extraArguments
        app.launch()
        return app
    }

    private func openGenres(in app: XCUIApplication) {
        let libraryDestination = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Library")
        ).firstMatch
        XCTAssertTrue(libraryDestination.waitForExistence(timeout: 5))
        libraryDestination.tap()

        let genresLink = app.buttons["library-genres-link"]
        XCTAssertTrue(genresLink.waitForExistence(timeout: 3))
        XCTAssertFalse(genresLink.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(genresLink.isHittable)
        genresLink.tap()

        XCTAssertTrue(element(in: app, identifier: "genres-screen").waitForExistence(timeout: 3))
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
                "Genre accessibility hierarchy exposed forbidden connection data: \(forbiddenValue)"
            )
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
