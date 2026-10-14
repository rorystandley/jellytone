import XCTest
@testable import Jellytone

@MainActor
final class PlaylistFeatureStateTests: XCTestCase {
    func testLibraryPaginationDeduplicatesPlaylistIdentityAndTerminates() async {
        let state = PlaylistLibraryState()
        let scope = scope("account-a")

        await state.load(scope: scope) { _ in
            PlaylistPage(
                playlists: [playlist("one", "Same Name"), playlist("two", "Same Name")],
                hasMore: true,
                nextStartIndex: 2
            )
        }
        await state.loadMore(scope: scope) { startIndex in
            XCTAssertEqual(startIndex, 2)
            return PlaylistPage(
                playlists: [playlist("two", "Updated Duplicate"), playlist("three", "Third")],
                hasMore: false,
                nextStartIndex: 4
            )
        }

        XCTAssertEqual(state.playlists.map(\.id), ["one", "two", "three"])
        XCTAssertEqual(state.playlists[1].name, "Same Name")
        XCTAssertFalse(state.canLoadMore)
    }

    func testOlderLibraryResponseCannotOverwriteNewerRefresh() async {
        let state = PlaylistLibraryState()
        let scope = scope("account-a")
        let gate = PlaylistPageGate()

        let oldTask = Task {
            await state.load(scope: scope) { _ in try await gate.wait(for: "old") }
        }
        await gate.waitUntilRegistered("old")
        let newTask = Task {
            await state.refresh(scope: scope) { _ in try await gate.wait(for: "new") }
        }
        await gate.waitUntilRegistered("new")

        await gate.resume("new", with: PlaylistPage(
            playlists: [playlist("new", "Newest")], hasMore: false, nextStartIndex: 1
        ))
        await newTask.value
        await gate.resume("old", with: PlaylistPage(
            playlists: [playlist("old", "Stale")], hasMore: false, nextStartIndex: 1
        ))
        await oldTask.value

        XCTAssertEqual(state.playlists.map(\.id), ["new"])
    }

    func testSwitchingScopeRejectsResponseFromPreviousAccount() async {
        let state = PlaylistLibraryState()
        let oldScope = scope("old-account")
        let newScope = scope("new-account")
        let gate = PlaylistPageGate()

        let oldTask = Task {
            await state.load(scope: oldScope) { _ in try await gate.wait(for: "old") }
        }
        await gate.waitUntilRegistered("old")
        let newTask = Task {
            await state.load(scope: newScope) { _ in try await gate.wait(for: "new") }
        }
        await gate.waitUntilRegistered("new")

        await gate.resume("new", with: PlaylistPage(
            playlists: [playlist("new", "New Account")], hasMore: false, nextStartIndex: 1
        ))
        await newTask.value
        await gate.resume("old", with: PlaylistPage(
            playlists: [playlist("private-old", "Old Account")], hasMore: false, nextStartIndex: 1
        ))
        await oldTask.value

        XCTAssertEqual(state.playlists.map(\.id), ["new"])
    }

    func testCancelledLoadDoesNotSurfaceAnErrorOrCorruptState() async {
        let state = PlaylistLibraryState()
        let task = Task {
            await state.load(scope: scope("account-a")) { _ in
                try await Task.sleep(for: .seconds(30))
                return PlaylistPage(playlists: [], hasMore: false, nextStartIndex: 0)
            }
        }
        await Task.yield()

        task.cancel()
        await task.value

        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.playlists.isEmpty)
    }

    func testFailedRefreshPreservesLastCompleteLibrarySnapshot() async {
        let state = PlaylistLibraryState()
        let scope = scope("account-a")
        await state.load(scope: scope) { _ in
            PlaylistPage(playlists: [playlist("kept", "Kept")], hasMore: false, nextStartIndex: 1)
        }

        await state.refresh(scope: scope) { _ in throw SyntheticError.failed }

        XCTAssertEqual(state.playlists.map(\.id), ["kept"])
        XCTAssertNotNil(state.errorMessage)
    }

    func testDetailPaginationPreservesEveryOccurrenceAndServerOrder() async {
        let state = PlaylistDetailState()
        let scope = scope("account-a")
        let playlist = playlist("mix", "Mix")
        let repeatedTrack = track("track-same")

        await state.load(playlist: playlist, scope: scope) { _ in
            PlaylistEntryPage(
                entries: [
                    PlaylistEntry(id: "occurrence-1", track: repeatedTrack),
                    PlaylistEntry(id: "occurrence-2", track: repeatedTrack),
                ],
                hasMore: true,
                nextStartIndex: 2
            )
        }
        await state.loadMore(playlist: playlist, scope: scope) { startIndex in
            XCTAssertEqual(startIndex, 2)
            return PlaylistEntryPage(
                entries: [
                    PlaylistEntry(id: "occurrence-3", track: repeatedTrack),
                    PlaylistEntry(id: "occurrence-4", track: track("track-last")),
                ],
                hasMore: false,
                nextStartIndex: 4
            )
        }

        XCTAssertEqual(state.entries.map(\.id), [
            "occurrence-1", "occurrence-2", "occurrence-3", "occurrence-4",
        ])
        XCTAssertEqual(state.entries.map(\.track.id), [
            "track-same", "track-same", "track-same", "track-last",
        ])
    }

    func testDetailPaginationFailureRetainsCompleteEntriesForRetry() async {
        let state = PlaylistDetailState()
        let scope = scope("account-a")
        let playlist = playlist("mix", "Mix")
        await state.load(playlist: playlist, scope: scope) { _ in
            PlaylistEntryPage(
                entries: [PlaylistEntry(id: "kept-entry", track: track("kept-track"))],
                hasMore: true,
                nextStartIndex: 1
            )
        }

        await state.loadMore(playlist: playlist, scope: scope) { _ in throw SyntheticError.failed }

        XCTAssertEqual(state.entries.map(\.id), ["kept-entry"])
        XCTAssertNotNil(state.paginationError)
        XCTAssertTrue(state.canLoadMore)
    }

    func testDetailResponseFromPreviousPlaylistCannotLeakIntoSelection() async {
        let state = PlaylistDetailState()
        let scope = scope("account-a")
        let first = playlist("first", "First")
        let second = playlist("second", "Second")
        let gate = PlaylistEntryPageGate()

        let firstTask = Task {
            await state.load(playlist: first, scope: scope) { _ in try await gate.wait(for: "first") }
        }
        await gate.waitUntilRegistered("first")
        let secondTask = Task {
            await state.load(playlist: second, scope: scope) { _ in try await gate.wait(for: "second") }
        }
        await gate.waitUntilRegistered("second")

        await gate.resume("second", with: PlaylistEntryPage(
            entries: [PlaylistEntry(id: "second-entry", track: track("second-track"))],
            hasMore: false,
            nextStartIndex: 1
        ))
        await secondTask.value
        await gate.resume("first", with: PlaylistEntryPage(
            entries: [PlaylistEntry(id: "private-first-entry", track: track("first-track"))],
            hasMore: false,
            nextStartIndex: 1
        ))
        await firstTask.value

        XCTAssertEqual(state.entries.map(\.id), ["second-entry"])
    }

    func testSeedPaintsCachedSnapshotWithoutLoadingAndNeverClobbersLiveContent() async {
        let state = PlaylistLibraryState()
        let requestedScope = scope("account-a")

        state.seed([playlist("cached", "Cached")], scope: requestedScope)
        XCTAssertEqual(state.playlists.map(\.id), ["cached"])
        XCTAssertFalse(state.isLoading, "A cached paint must not show as loading")
        XCTAssertFalse(state.hasLoaded, "Seeding is not a completed network load")

        await state.refresh(scope: requestedScope) { _ in
            PlaylistPage(playlists: [self.playlist("fresh", "Fresh")], hasMore: false, nextStartIndex: 1)
        }
        XCTAssertEqual(state.playlists.map(\.id), ["fresh"])

        state.seed([playlist("stale", "Stale")], scope: requestedScope)
        XCTAssertEqual(state.playlists.map(\.id), ["fresh"],
                       "A stale cache read must not replace live results")
    }

    private func scope(_ account: String) -> PlaylistFeatureScope {
        PlaylistFeatureScope(serverID: "server", accountID: account, libraryID: "music")
    }

    private func playlist(_ id: String, _ name: String) -> Playlist {
        Playlist(id: id, name: name, imageTag: nil, itemCount: nil)
    }

    private func track(_ id: String) -> Track {
        Track(
            id: id,
            name: "Track \(id)",
            artist: "Synthetic Artist",
            album: "Synthetic Album",
            index: nil,
            disc: nil,
            durationTicks: 30_000_000
        )
    }
}

private enum SyntheticError: Error {
    case failed
}

private actor PlaylistPageGate {
    private var continuations: [String: CheckedContinuation<PlaylistPage, Error>] = [:]

    func wait(for key: String) async throws -> PlaylistPage {
        try await withCheckedThrowingContinuation { continuations[key] = $0 }
    }

    func waitUntilRegistered(_ key: String) async {
        while continuations[key] == nil { await Task.yield() }
    }

    func resume(_ key: String, with page: PlaylistPage) {
        continuations.removeValue(forKey: key)?.resume(returning: page)
    }
}

private actor PlaylistEntryPageGate {
    private var continuations: [String: CheckedContinuation<PlaylistEntryPage, Error>] = [:]

    func wait(for key: String) async throws -> PlaylistEntryPage {
        try await withCheckedThrowingContinuation { continuations[key] = $0 }
    }

    func waitUntilRegistered(_ key: String) async {
        while continuations[key] == nil { await Task.yield() }
    }

    func resume(_ key: String, with page: PlaylistEntryPage) {
        continuations.removeValue(forKey: key)?.resume(returning: page)
    }
}
