import XCTest
@testable import Jellytone

@MainActor
final class HomeFeatureStateTests: XCTestCase {
    func testCachedSnapshotIsPresentedBeforeRefreshCompletes() async {
        let state = HomeFeatureState()
        let gate = HomeRefreshGate()
        let cached = snapshot(albumID: "cached-album", trackID: "cached-track")
        let task = Task {
            await state.load(scope: scope("account"), cached: cached) {
                await gate.wait(for: "refresh")
            }
        }
        await gate.waitUntilRegistered("refresh")

        XCTAssertEqual(state.snapshot.recentlyAddedAlbums.map(\.id), ["cached-album"])
        XCTAssertEqual(state.snapshot.recentlyPlayedTracks.map(\.id), ["cached-track"])
        XCTAssertTrue(state.isRefreshing)

        await gate.resume("refresh", with: .success(snapshot(albumID: "fresh-album", trackID: "fresh-track")))
        await task.value
        XCTAssertEqual(state.snapshot.recentlyAddedAlbums.map(\.id), ["fresh-album"])
        XCTAssertFalse(state.isRefreshing)
    }

    func testFailureKeepsCachedSnapshotAndExposesSafeSectionErrors() async {
        let state = HomeFeatureState()
        let cached = snapshot(albumID: "kept-album", trackID: "kept-track")
        await state.load(scope: scope("account"), cached: cached) {
            .failure(HomeShelfRefreshFailure(
                recentlyAddedMessage: "Couldn’t refresh recently added albums.",
                recentlyPlayedMessage: "Couldn’t refresh recently played music."
            ))
        }

        XCTAssertEqual(state.snapshot.recentlyAddedAlbums.map(\.id), ["kept-album"])
        XCTAssertEqual(state.snapshot.recentlyPlayedTracks.map(\.id), ["kept-track"])
        XCTAssertNotNil(state.recentlyAddedErrorMessage)
        XCTAssertNotNil(state.recentlyPlayedErrorMessage)
    }

    func testOlderScopeResponseCannotReplaceNewerScope() async {
        let state = HomeFeatureState()
        let gate = HomeRefreshGate()
        let oldTask = Task {
            await state.load(scope: scope("old"), cached: nil) { await gate.wait(for: "old") }
        }
        await gate.waitUntilRegistered("old")
        let newTask = Task {
            await state.load(scope: scope("new"), cached: nil) { await gate.wait(for: "new") }
        }
        await gate.waitUntilRegistered("new")

        await gate.resume("new", with: .success(snapshot(albumID: "new", trackID: "new")))
        await newTask.value
        await gate.resume("old", with: .success(snapshot(albumID: "old", trackID: "old")))
        await oldTask.value

        XCTAssertEqual(state.snapshot.recentlyAddedAlbums.map(\.id), ["new"])
        XCTAssertEqual(state.snapshot.recentlyPlayedTracks.map(\.id), ["new"])
    }

    private func scope(_ accountID: String) -> HomeFeatureScope {
        HomeFeatureScope(serverID: "server", accountID: accountID, libraryID: "library")
    }

    private func snapshot(albumID: String, trackID: String) -> HomeShelfSnapshot {
        HomeShelfSnapshot(
            recentlyAddedAlbums: [Album(id: albumID, name: "Album", artist: "Artist", productionYear: nil, imageTag: nil)],
            recentlyPlayedTracks: [Track(id: trackID, name: "Track", artist: "Artist", album: "Album", index: nil, disc: nil, durationTicks: nil)]
        )
    }
}

private actor HomeRefreshGate {
    private var continuations: [String: CheckedContinuation<Result<HomeShelfSnapshot, HomeShelfRefreshFailure>, Never>] = [:]

    func wait(for key: String) async -> Result<HomeShelfSnapshot, HomeShelfRefreshFailure> {
        await withCheckedContinuation { continuations[key] = $0 }
    }

    func waitUntilRegistered(_ key: String) async {
        while continuations[key] == nil { await Task.yield() }
    }

    func resume(_ key: String, with result: Result<HomeShelfSnapshot, HomeShelfRefreshFailure>) {
        continuations.removeValue(forKey: key)?.resume(returning: result)
    }
}
