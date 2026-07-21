import XCTest
@testable import Jellytone

@MainActor
final class ArtistFeatureStateTests: XCTestCase {
    func testLibraryPaginationDeduplicatesArtistIdentity() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")

        await state.load(scope: requestedScope) { _ in
            ArtistPage(
                artists: [artist("aurora", "Aurora"), artist("bowie", "Bowie")],
                hasMore: true,
                nextStartIndex: 2
            )
        }
        await state.loadMore(scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 2)
            return ArtistPage(
                artists: [artist("bowie", "Changed"), artist("cave", "Cave")],
                hasMore: false,
                nextStartIndex: 4
            )
        }

        XCTAssertEqual(state.artists.map(\.id), ["aurora", "bowie", "cave"])
        XCTAssertEqual(state.artists[1].name, "Bowie")
        XCTAssertFalse(state.canLoadMore)
    }

    func testLibraryRefreshFailurePreservesSnapshot() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            ArtistPage(artists: [artist("kept", "Kept")], hasMore: false, nextStartIndex: 1)
        }

        await state.refresh(scope: requestedScope) { _ in throw ArtistSyntheticError.failed }

        XCTAssertEqual(state.artists.map(\.id), ["kept"])
        XCTAssertNotNil(state.errorMessage)
    }

    func testLibraryScopeChangeRejectsStaleResponse() async {
        let state = ArtistLibraryState()
        let gate = ArtistPageGate()
        let oldScope = scope("old")
        let newScope = scope("new")

        let oldTask = Task {
            await state.load(scope: oldScope) { _ in try await gate.wait(for: "old") }
        }
        await gate.waitUntilRegistered("old")
        let newTask = Task {
            await state.load(scope: newScope) { _ in try await gate.wait(for: "new") }
        }
        await gate.waitUntilRegistered("new")

        await gate.resume("new", with: ArtistPage(
            artists: [artist("new", "New")], hasMore: false, nextStartIndex: 1
        ))
        await newTask.value
        await gate.resume("old", with: ArtistPage(
            artists: [artist("private-old", "Old")], hasMore: false, nextStartIndex: 1
        ))
        await oldTask.value

        XCTAssertEqual(state.artists.map(\.id), ["new"])
    }

    func testLibraryPaginationErrorKeepsLoadedArtistsAndAllowsRetry() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            ArtistPage(artists: [artist("first", "First")], hasMore: true, nextStartIndex: 1)
        }

        await state.loadMore(scope: requestedScope) { _ in throw ArtistSyntheticError.failed }

        XCTAssertEqual(state.artists.map(\.id), ["first"])
        XCTAssertNotNil(state.paginationError)
        XCTAssertTrue(state.canLoadMore)

        await state.loadMore(scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 1)
            return ArtistPage(artists: [artist("second", "Second")], hasMore: false, nextStartIndex: 2)
        }

        XCTAssertEqual(state.artists.map(\.id), ["first", "second"])
        XCTAssertNil(state.paginationError)
        XCTAssertFalse(state.canLoadMore)
    }

    func testLoadAllRemainingPagesUntilExhaustedForTheAlphabetIndex() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            ArtistPage(artists: [artist("a", "A")], hasMore: true, nextStartIndex: 1)
        }

        await state.loadAllRemaining(scope: requestedScope) { startIndex in
            switch startIndex {
            case 1: return ArtistPage(artists: [artist("b", "B")], hasMore: true, nextStartIndex: 2)
            case 2: return ArtistPage(artists: [artist("c", "C")], hasMore: false, nextStartIndex: 3)
            default:
                XCTFail("Unexpected cursor \(startIndex)")
                return ArtistPage(artists: [], hasMore: false, nextStartIndex: startIndex)
            }
        }

        XCTAssertEqual(state.artists.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(state.canLoadMore)
    }

    func testLoadAllRemainingStopsOnPaginationErrorAndOnStuckCursor() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            ArtistPage(artists: [artist("a", "A")], hasMore: true, nextStartIndex: 1)
        }

        var calls = 0
        await state.loadAllRemaining(scope: requestedScope) { _ in
            calls += 1
            throw ArtistSyntheticError.failed
        }
        XCTAssertEqual(calls, 1, "A pagination failure must stop the backfill, not retry forever")
        XCTAssertEqual(state.artists.map(\.id), ["a"])
        XCTAssertNotNil(state.paginationError)

        // Retry succeeds but the server claims more while never advancing the
        // cursor: the backfill must bail out rather than loop.
        var stuckCalls = 0
        await state.loadAllRemaining(scope: requestedScope) { startIndex in
            stuckCalls += 1
            return ArtistPage(artists: [], hasMore: true, nextStartIndex: startIndex)
        }
        XCTAssertEqual(stuckCalls, 1)
    }

    func testSeedPaintsCachedSnapshotWithoutLoadingAndRefreshReplacesIt() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")

        state.seed([artist("cached", "Cached")], scope: requestedScope)

        XCTAssertEqual(state.artists.map(\.id), ["cached"])
        XCTAssertFalse(state.isLoading, "A cached paint must not show as loading")
        XCTAssertFalse(state.hasLoaded, "Seeding is not a completed network load")

        await state.refresh(scope: requestedScope) { _ in
            ArtistPage(artists: [artist("fresh", "Fresh")], hasMore: false, nextStartIndex: 1)
        }

        XCTAssertEqual(state.artists.map(\.id), ["fresh"])
        XCTAssertTrue(state.hasLoaded)
    }

    func testSeedNeverClobbersLiveContentAndKeepsCacheOnRefreshFailure() async {
        let state = ArtistLibraryState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            ArtistPage(artists: [artist("live", "Live")], hasMore: false, nextStartIndex: 1)
        }

        state.seed([artist("stale", "Stale")], scope: requestedScope)
        XCTAssertEqual(state.artists.map(\.id), ["live"],
                       "A stale cache read must not replace live results")

        let freshState = ArtistLibraryState()
        freshState.seed([artist("cached", "Cached")], scope: requestedScope)
        await freshState.refresh(scope: requestedScope) { _ in throw ArtistSyntheticError.failed }
        XCTAssertEqual(freshState.artists.map(\.id), ["cached"],
                       "An offline refresh keeps the cached snapshot on screen")
        XCTAssertNotNil(freshState.errorMessage)
    }

    private func scope(_ account: String) -> ArtistFeatureScope {
        ArtistFeatureScope(serverID: "server", accountID: account, libraryID: "music")
    }

    private func artist(_ id: String, _ name: String) -> Artist {
        Artist(id: id, name: name, imageTag: nil)
    }
}

private enum ArtistSyntheticError: Error {
    case failed
}

private actor ArtistPageGate {
    private var continuations: [String: CheckedContinuation<ArtistPage, Error>] = [:]

    func wait(for key: String) async throws -> ArtistPage {
        try await withCheckedThrowingContinuation { continuations[key] = $0 }
    }

    func waitUntilRegistered(_ key: String) async {
        while continuations[key] == nil { await Task.yield() }
    }

    func resume(_ key: String, with page: ArtistPage) {
        continuations.removeValue(forKey: key)?.resume(returning: page)
    }
}
