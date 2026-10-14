import XCTest
@testable import Jellytone

final class PlaylistRenameTests: XCTestCase {
    func testValidationTrimsUnicodeAndRejectsUnsafeNames() throws {
        XCTAssertEqual(try PlaylistRenameValidation.validate("  Café 東京 🎧  "), "Café 東京 🎧")
        XCTAssertThrowsError(try PlaylistRenameValidation.validate("\n"))
        XCTAssertThrowsError(try PlaylistRenameValidation.validate("bad\u{0000}name"))
        XCTAssertThrowsError(try PlaylistRenameValidation.validate(String(repeating: "x", count: 256)))
    }

    func testRapidRenamesCoalesceToOneScopedMutationAndPreservePlaylistIdentity() throws {
        let first = try PlaylistRenameValidation.validate("First")
        let second = try PlaylistRenameValidation.validate("Second")
        var mutation = PlaylistRenameMutation(id: "playlist-rename:s:a:p", serverID: "s", accountID: "a", playlistID: "p", baseRevision: "name:Original", baseName: "Original", desiredName: first, sequence: 1, attempts: 0, nextRetryAt: 0, state: .pending)
        mutation.desiredName = second
        mutation.sequence = 2
        XCTAssertEqual(mutation.id, "playlist-rename:s:a:p")
        XCTAssertEqual(mutation.desiredName, "Second")
        XCTAssertEqual(mutation.playlistID, "p")
    }

    func testConflictChoicesAreExplicitAndUseMyNameRebases() {
        let remote = JellyfinAPI.PlaylistRenameRemoteState(revision: "name:Remote", name: "Remote")
        let mutation = PlaylistRenameMutation(id: "m", serverID: "s", accountID: "a", playlistID: "p", baseRevision: "name:Old", baseName: "Old", desiredName: "Mine", sequence: 1, attempts: 2, nextRetryAt: 10, state: .conflict)
        let keep = mutation.resolving(.keepServerVersion, remote: remote)
        XCTAssertEqual(keep.state, .completed); XCTAssertEqual(keep.desiredName, "Remote")
        let use = mutation.resolving(.useMyName, remote: remote)
        XCTAssertEqual(use.state, .pending); XCTAssertEqual(use.baseRevision, "name:Remote"); XCTAssertEqual(use.desiredName, "Mine")
    }

    func testMembershipAndOrderAreOutsideRenameMutation() {
        let mutation = PlaylistRenameMutation(id: "m", serverID: "s", accountID: "a", playlistID: "p", baseRevision: "name:Old", baseName: "Old", desiredName: "New", sequence: 1, attempts: 0, nextRetryAt: 0, state: .pending)
        XCTAssertFalse(String(describing: mutation).contains("membership"))
        XCTAssertFalse(String(describing: mutation).contains("order"))
    }
}
