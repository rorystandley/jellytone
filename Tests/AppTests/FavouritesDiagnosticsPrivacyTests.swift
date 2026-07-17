import XCTest
@testable import JellyfinAudio

final class FavouritesDiagnosticsPrivacyTests: XCTestCase {
    func testFavouriteOperationsAreAllowlistedWithoutPrivateScopeValues() {
        for operation in ["favourite_artists", "favourite_albums", "favourite_tracks"] {
            let message = Diagnostics.renderedEvent("response_received", [
                "operation": operation, "status": 206, "library_id": "private-library",
                "account_id": "private-account", "endpoint": "https://private.invalid/token"
            ])
            XCTAssertEqual(message, "JA_DIAG response_received operation=\(operation) status=206")
            XCTAssertFalse(message.contains("private"))
        }
    }
}
