import XCTest
@testable import Jellytone

@MainActor
final class FavouritesFeatureStateTests: XCTestCase {
    func testSectionsPaginateIndependentlyAndDeduplicateStableArtistAlbumIDs() async {
        let state = FavouritesState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            FavouriteArtistPage(artists: [self.artist("a1", "Same"), self.artist("a2", "Same")], hasMore: true, nextStartIndex: 2)
        } loadAlbums: { _ in
            FavouriteAlbumPage(albums: [self.album("b1", "Same")], hasMore: true, nextStartIndex: 1)
        } loadTracks: { _ in
            FavouriteTrackPage(occurrences: [self.occurrence("o1", trackID: "t1")], hasMore: true, nextStartIndex: 1)
        }

        await state.loadMoreArtists(scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 2)
            return FavouriteArtistPage(artists: [self.artist("a2", "Changed"), self.artist("a3", "Unicode あ")], hasMore: false, nextStartIndex: 4)
        }
        await state.loadMoreAlbums(scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 1)
            return FavouriteAlbumPage(albums: [self.album("b1", "Changed"), self.album("b2", "Second")], hasMore: false, nextStartIndex: 3)
        }
        await state.loadMoreTracks(scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 1)
            return FavouriteTrackPage(occurrences: [self.occurrence("o2", trackID: "t1")], hasMore: false, nextStartIndex: 2)
        }

        XCTAssertEqual(state.artists.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(state.artists[1].name, "Same")
        XCTAssertEqual(state.albums.map(\.id), ["b1", "b2"])
        XCTAssertEqual(state.albums[0].name, "Same")
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["o1", "o2"])
        XCTAssertEqual(state.trackOccurrences.map(\.track.id), ["t1", "t1"])
    }

    func testOneSectionFailurePreservesItsSnapshotWithoutErasingOtherSections() async {
        let state = FavouritesState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            FavouriteArtistPage(artists: [self.artist("a1", "Kept")], hasMore: false, nextStartIndex: 1)
        } loadAlbums: { _ in
            FavouriteAlbumPage(albums: [self.album("b1", "Kept")], hasMore: false, nextStartIndex: 1)
        } loadTracks: { _ in
            FavouriteTrackPage(occurrences: [self.occurrence("o1", trackID: "t1")], hasMore: false, nextStartIndex: 1)
        }

        await state.refresh(scope: requestedScope) { _ in throw FavouritesSyntheticError.failed } loadAlbums: { _ in
            FavouriteAlbumPage(albums: [self.album("b2", "Replacement")], hasMore: false, nextStartIndex: 1)
        } loadTracks: { _ in
            FavouriteTrackPage(occurrences: [self.occurrence("o2", trackID: "t2")], hasMore: false, nextStartIndex: 1)
        }

        XCTAssertEqual(state.artists.map(\.id), ["a1"])
        XCTAssertNotNil(state.artistErrorMessage)
        XCTAssertEqual(state.albums.map(\.id), ["b2"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["o2"])
    }

    func testPaginationFailurePreservesEachValidSnapshotAndCanRetry() async {
        let state = FavouritesState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            FavouriteArtistPage(artists: [self.artist("a1", "Artist")], hasMore: true, nextStartIndex: 1)
        } loadAlbums: { _ in
            FavouriteAlbumPage(albums: [self.album("b1", "Album")], hasMore: true, nextStartIndex: 1)
        } loadTracks: { _ in
            FavouriteTrackPage(occurrences: [self.occurrence("o1", trackID: "t1")], hasMore: true, nextStartIndex: 1)
        }

        await state.loadMoreArtists(scope: requestedScope) { _ in throw FavouritesSyntheticError.failed }
        await state.loadMoreAlbums(scope: requestedScope) { _ in throw FavouritesSyntheticError.failed }
        await state.loadMoreTracks(scope: requestedScope) { _ in throw FavouritesSyntheticError.failed }

        XCTAssertEqual(state.artists.map(\.id), ["a1"])
        XCTAssertEqual(state.albums.map(\.id), ["b1"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["o1"])
        XCTAssertNotNil(state.artistPaginationError)
        XCTAssertNotNil(state.albumPaginationError)
        XCTAssertNotNil(state.trackPaginationError)
        XCTAssertTrue(state.canLoadMoreArtists)
        XCTAssertTrue(state.canLoadMoreAlbums)
        XCTAssertTrue(state.canLoadMoreTracks)
    }

    func testScopeChangeRejectsAllStaleSectionResponses() async {
        let state = FavouritesState()
        let gate = FavouritesGate()
        let oldScope = scope("old")
        let newScope = scope("new")

        let oldTask = Task { await state.load(scope: oldScope, loadArtists: { _ in try await gate.artists("old") }, loadAlbums: { _ in try await gate.albums("old") }, loadTracks: { _ in try await gate.tracks("old") }) }
        await gate.waitUntilRegistered("old")
        let newTask = Task { await state.load(scope: newScope, loadArtists: { _ in try await gate.artists("new") }, loadAlbums: { _ in try await gate.albums("new") }, loadTracks: { _ in try await gate.tracks("new") }) }
        await gate.waitUntilRegistered("new")
        await gate.resume("new")
        await newTask.value
        await gate.resume("old")
        await oldTask.value

        XCTAssertEqual(state.artists.map(\.id), ["new-artist"])
        XCTAssertEqual(state.albums.map(\.id), ["new-album"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["new-occurrence"])
    }

    private func scope(_ account: String) -> FavouritesFeatureScope {
        FavouritesFeatureScope(serverID: "server", accountID: account, libraryID: "library")
    }

    private func artist(_ id: String, _ name: String) -> Artist { Artist(id: id, name: name, imageTag: nil) }
    private func album(_ id: String, _ name: String) -> Album { Album(id: id, name: name, artist: "Artist", productionYear: nil, imageTag: nil) }
    private func occurrence(_ id: String, trackID: String) -> FavouriteTrackOccurrence {
        FavouriteTrackOccurrence(id: id, track: Track(id: trackID, name: "Track", artist: "Artist", album: "Album", index: nil, disc: nil, durationTicks: nil))
    }
}

private enum FavouritesSyntheticError: Error { case failed }

private actor FavouritesGate {
    private var artistContinuations: [String: CheckedContinuation<FavouriteArtistPage, Error>] = [:]
    private var albumContinuations: [String: CheckedContinuation<FavouriteAlbumPage, Error>] = [:]
    private var trackContinuations: [String: CheckedContinuation<FavouriteTrackPage, Error>] = [:]

    func artists(_ key: String) async throws -> FavouriteArtistPage {
        try await withCheckedThrowingContinuation { artistContinuations[key] = $0 }
    }
    func albums(_ key: String) async throws -> FavouriteAlbumPage {
        try await withCheckedThrowingContinuation { albumContinuations[key] = $0 }
    }
    func tracks(_ key: String) async throws -> FavouriteTrackPage {
        try await withCheckedThrowingContinuation { trackContinuations[key] = $0 }
    }
    func waitUntilRegistered(_ key: String) async {
        while artistContinuations[key] == nil || albumContinuations[key] == nil || trackContinuations[key] == nil {
            await Task.yield()
        }
    }
    func resume(_ key: String) {
        artistContinuations.removeValue(forKey: key)?.resume(returning: FavouriteArtistPage(artists: [Artist(id: "\(key)-artist", name: key, imageTag: nil)], hasMore: false, nextStartIndex: 1))
        albumContinuations.removeValue(forKey: key)?.resume(returning: FavouriteAlbumPage(albums: [Album(id: "\(key)-album", name: key, artist: key, productionYear: nil, imageTag: nil)], hasMore: false, nextStartIndex: 1))
        trackContinuations.removeValue(forKey: key)?.resume(returning: FavouriteTrackPage(occurrences: [FavouriteTrackOccurrence(id: "\(key)-occurrence", track: Track(id: "\(key)-track", name: key, artist: key, album: key, index: nil, disc: nil, durationTicks: nil))], hasMore: false, nextStartIndex: 1))
    }
}
