import XCTest
@testable import Jellytone

/// Regression coverage for the airplane-mode fix: connectivity failures from a
/// background refresh must never raise the blocking "Something went wrong"
/// alert or replace cached content that is already on screen.
final class OfflineErrorTests: XCTestCase {
    func testConnectivityFailuresClassifyAsOffline() {
        XCTAssertTrue(OfflineError.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(OfflineError.isOffline(URLError(.networkConnectionLost)))
        XCTAssertTrue(OfflineError.isOffline(URLError(.cannotConnectToHost)))
        XCTAssertTrue(OfflineError.isOffline(URLError(.cannotFindHost)))
        XCTAssertTrue(OfflineError.isOffline(URLError(.dnsLookupFailed)))
        XCTAssertTrue(OfflineError.isOffline(URLError(.timedOut)))
        XCTAssertTrue(OfflineError.isOffline(URLError(.dataNotAllowed)))
    }

    func testServerAndAuthFailuresAreNotOffline() {
        XCTAssertFalse(OfflineError.isOffline(APIError.httpStatus(500)))
        XCTAssertFalse(OfflineError.isOffline(APIError.notAuthenticated))
        XCTAssertFalse(OfflineError.isOffline(APIError.invalidPayload))
        XCTAssertFalse(OfflineError.isOffline(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(OfflineError.isOffline(CancellationError()))
    }

    func testBackgroundRefreshAlertIsSilentOfflineAndVisibleOtherwise() {
        XCTAssertNil(OfflineError.backgroundRefreshAlert(for: URLError(.notConnectedToInternet)))
        XCTAssertNil(OfflineError.backgroundRefreshAlert(for: URLError(.cannotConnectToHost)))
        XCTAssertNotNil(OfflineError.backgroundRefreshAlert(for: APIError.httpStatus(500)))
    }

    func testHomeShelfOfflineFailuresStaySilentOverCachedContent() {
        let failures: [(message: String, isOffline: Bool)] = [
            ("Recently added albums couldn’t be refreshed.", true),
            ("Recently played music couldn’t be refreshed.", true),
        ]
        XCTAssertNil(OfflineError.visibleFailureMessage(failures, hasCachedContent: true))
    }

    func testHomeShelfOfflineFailuresRemainVisibleWithNothingCached() {
        let failures: [(message: String, isOffline: Bool)] = [
            ("Recently added albums couldn’t be refreshed.", true),
        ]
        XCTAssertEqual(
            OfflineError.visibleFailureMessage(failures, hasCachedContent: false),
            "Recently added albums couldn’t be refreshed."
        )
    }

    func testHomeShelfServerFailuresRemainVisibleOverCachedContent() {
        let failures: [(message: String, isOffline: Bool)] = [
            ("Recently added albums couldn’t be refreshed.", true),
            ("Recently played music couldn’t be refreshed.", false),
        ]
        XCTAssertEqual(
            OfflineError.visibleFailureMessage(failures, hasCachedContent: true),
            "Recently played music couldn’t be refreshed."
        )
        XCTAssertNil(OfflineError.visibleFailureMessage([], hasCachedContent: false))
    }
}
