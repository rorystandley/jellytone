import XCTest
@testable import JellyfinAudio

final class DiagnosticsPrivacyTests: XCTestCase {
    func testExistingDiagnosticShapeKeepsOnlyBoundedAllowlistedFields() {
        let message = Diagnostics.renderedEvent("response_received", [
            "bytes": 1_500_000_000,
            "operation": "playback_progress",
            "status": 204,
            "unexpected": "private library content",
        ])

        XCTAssertEqual(
            message,
            "JA_DIAG response_received bytes=1000000000 operation=playback_progress status=204"
        )
    }

    func testPlaybackReportingUsesBoundedAllowlistedLifecycleFields() {
        let message = Diagnostics.renderedEvent("playback_reporting", [
            "lifecycle": Diagnostics.PlaybackLifecycle.failed.rawValue,
            "method": Diagnostics.PlaybackMethod.transcode.rawValue,
            "operation": Diagnostics.ReportingOperation.stop.rawValue,
            "position_seconds": Double.greatestFiniteMagnitude,
            "reason": Diagnostics.ReportingReason.server.rawValue,
            "status": Diagnostics.ReportingStatus.failed.rawValue,
        ])

        XCTAssertEqual(
            message,
            "JA_DIAG playback_reporting lifecycle=failed method=transcode operation=stop position_seconds=604800 reason=server status=failed"
        )
    }

    func testSeededSensitiveFixturesCannotReachAnyDiagnosticSinkPayload() {
        var generator = SeededSensitiveFixtureGenerator(seed: 0x5EED_CAFE)
        let token = generator.secret(prefix: "token")
        let username = generator.secret(prefix: "user")
        let itemID = generator.secret(prefix: "item")
        let title = generator.secret(prefix: "library")
        let server = "https://\(generator.secret(prefix: "host")).example:8920/Users/\(username)/Items?api_key=\(token)"
        let authorization = "MediaBrowser Token=\(token)"

        let message = Diagnostics.renderedEvent("playback_reporting", [
            "authorization": authorization,
            "item_id": itemID,
            "lifecycle": server,
            "method": username,
            "operation": server,
            "position_seconds": token,
            "reason": title,
            "server_url": server,
            "status": authorization,
            "username": username,
        ])
        let rejectedEvent = Diagnostics.renderedEvent(title, [
            "code": 123_456,
            "operation": "playback_progress",
            "status": 204,
        ])

        XCTAssertEqual(message, "JA_DIAG playback_reporting")
        XCTAssertEqual(rejectedEvent, "JA_DIAG diagnostic_event_rejected")
        for sensitiveValue in [token, username, itemID, title, server, authorization, "api_key", "example"] {
            XCTAssertFalse(message.localizedCaseInsensitiveContains(sensitiveValue), sensitiveValue)
            XCTAssertFalse(rejectedEvent.localizedCaseInsensitiveContains(sensitiveValue), sensitiveValue)
        }
    }

    func testErrorDomainIsCategorizedRatherThanPersistedVerbatim() {
        let privateDomain = "https://private-host.example/user@example.com?token=secret"
        let message = Diagnostics.renderedEvent("request_failed", [
            "code": -1_009,
            "domain": privateDomain,
            "operation": "playback_progress",
        ])

        XCTAssertEqual(message, "JA_DIAG request_failed code=-1009 domain=other operation=playback_progress")
        XCTAssertFalse(message.contains(privateDomain))
    }
}

private struct SeededSensitiveFixtureGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func secret(prefix: String) -> String {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return "\(prefix)-\(String(state, radix: 16))"
    }
}
