import XCTest

@MainActor
final class TrackCatalogUITests: XCTestCase {
    func testTracksDestinationSupportsAccessibleRowsAndMissingMetadata() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-tracks"]
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
    }

}
