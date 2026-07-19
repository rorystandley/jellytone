import XCTest

@MainActor
final class TrackCatalogUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCUIDevice.shared.orientation = .portrait
    }

    func testTracksDestinationSupportsAccessibleRowsAndMissingMetadata() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-tracks", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch()
        let library = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Library")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5)); library.tap()
        let link = app.buttons["library-tracks-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 3)); XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.navigationBars["Tracks"].waitForExistence(timeout: 3))
        let first = app.descendants(matching: .any)["track-catalog-row-track-catalog:0:track-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3)); XCTAssertTrue(first.isHittable)
        XCTAssertTrue(first.label.contains("A First Song"))
        XCTAssertTrue(app.descendants(matching: .any)["track-catalog-row-track-catalog:1:track-2"].exists)
        XCTAssertFalse(app.buttons["Favourite A First Song"].exists)
        XCTAssertFalse(app.buttons["Unfavourite A First Song"].exists)
        capture("track-catalog-large-type", app: app)
    }

    func testTrackCatalogueLoadingEmptyAndPaginationFailureStates() {
        var app = launchTracks(["--ui-testing-tracks-loading"])
        openTracks(in: app)
        XCTAssertTrue(app.staticTexts["Loading tracks"].waitForExistence(timeout: 4))
        app.terminate()

        app = launchTracks(["--ui-testing-tracks-empty"])
        openTracks(in: app)
        XCTAssertTrue(app.staticTexts["No tracks found"].waitForExistence(timeout: 4))
        app.terminate()

        app = launchTracks(["--ui-testing-tracks-pagination-error"])
        openTracks(in: app)
        let retry = app.buttons["track-catalog-retry-more"]
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 4))
        XCTAssertTrue(retry.isHittable)
    }

    private func launchTracks(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-testing-tracks"] + extra; app.launch(); return app
    }

    private func openTracks(in app: XCUIApplication) {
        let library = app.tabBars.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 4)); library.tap()
        let link = app.buttons["library-tracks-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 3)); link.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

}
