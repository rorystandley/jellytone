import XCTest

@MainActor
final class DownloadsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testDownloadsTabShowsEmptyStateAndAlbumHeaderOffersDownload() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-music-shell", "--ui-testing-library"]
        app.launch()

        let downloadsTab = app.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", "Downloads"))
            .firstMatch
        XCTAssertTrue(downloadsTab.waitForExistence(timeout: 4))
        downloadsTab.tap()

        XCTAssertTrue(app.descendants(matching: .any)["downloads-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No downloads yet"].exists)

        // The album detail header exposes the download action.
        let libraryTab = app.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", "Library"))
            .firstMatch
        libraryTab.tap()
        let album = app.descendants(matching: .any)["library-album-album-artwork"]
        XCTAssertTrue(album.waitForExistence(timeout: 4))
        album.tap()
        let download = app.buttons["album-download"]
        XCTAssertTrue(download.waitForExistence(timeout: 4))
        XCTAssertEqual(download.label, "Download")
    }
}
