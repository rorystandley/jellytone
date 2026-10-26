import XCTest
@testable import Jellytone

final class GenreDiagnosticsPrivacyTests: XCTestCase {
    func testGenreOperationsExposeOnlyAllowlistedOperationAndStatus() {
        XCTAssertEqual(
            Diagnostics.renderedEvent("request_started", privateFields(operation: "genres")),
            "JA_DIAG request_started operation=genres"
        )
        XCTAssertEqual(
            Diagnostics.renderedEvent("response_received", privateFields(operation: "genre_albums")),
            "JA_DIAG response_received operation=genre_albums status=206"
        )
        XCTAssertEqual(
            Diagnostics.renderedEvent("response_received", privateFields(operation: "genre_tracks")),
            "JA_DIAG response_received operation=genre_tracks status=206"
        )
    }

    func testGenreDiagnosticsRejectPrivateValuesEvenWhenInjectedIntoAllowlistedKeys() {
        for operation in ["genres", "genre_albums", "genre_tracks"] {
            let message = Diagnostics.renderedEvent("response_received", [
                "operation": operation,
                "status": "private-status-value",
                "genre_id": "genre-private-91c6",
                "genre_name": "Private Listening Genre",
                "item_id": "item-private-b087",
                "account_id": "account-private-2705",
                "library_id": "library-private-1f33",
                "endpoint": "https://private.example.invalid/jellyfin/Genres",
            ])

            XCTAssertEqual(message, "JA_DIAG response_received operation=\(operation)")
            for forbidden in forbiddenValues {
                XCTAssertFalse(message.localizedCaseInsensitiveContains(forbidden), forbidden)
            }
        }
    }

    func testUnregisteredGenreOperationCannotReachDiagnosticPayload() {
        let message = Diagnostics.renderedEvent("request_failed", [
            "operation": "genre-private-91c6",
            "status": 503,
            "endpoint": "https://private.example.invalid",
        ])

        XCTAssertEqual(message, "JA_DIAG request_failed status=503")
        for forbidden in forbiddenValues {
            XCTAssertFalse(message.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    private func privateFields(operation: String) -> [String: CustomStringConvertible] {
        var fields: [String: CustomStringConvertible] = [
            "operation": operation,
            "genre_id": "genre-private-91c6",
            "genre_name": "Private Listening Genre",
            "item_id": "item-private-b087",
            "account_id": "account-private-2705",
            "library_id": "library-private-1f33",
            "endpoint": "https://private.example.invalid/jellyfin/Genres",
        ]
        fields["status"] = operation == "genres" ? "private-status-value" : "206"
        return fields
    }

    private var forbiddenValues: [String] {
        [
            "genre-private-91c6",
            "Private Listening Genre",
            "item-private-b087",
            "account-private-2705",
            "library-private-1f33",
            "private.example.invalid",
            "/jellyfin/Genres",
        ]
    }
}
