import XCTest
@testable import Jellytone

@MainActor
final class GenreFeatureStateTests: XCTestCase {
    func testLibraryPaginationDeduplicatesGenreIdentity() async {
        let state = GenreLibraryState()
        let requestedScope = scope("account-a")

        await state.load(scope: requestedScope) { _ in
            GenrePage(
                genres: [genre("rock", "Rock"), genre("jazz", "Jazz")],
                hasMore: true,
                nextStartIndex: 2
            )
        }
        await state.loadMore(scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 2)
            return GenrePage(
                genres: [genre("jazz", "Changed"), genre("soul", "Soul")],
                hasMore: false,
                nextStartIndex: 4
            )
        }

        XCTAssertEqual(state.genres.map(\.id), ["rock", "jazz", "soul"])
        XCTAssertEqual(state.genres[1].name, "Jazz")
        XCTAssertFalse(state.canLoadMore)
    }

    func testLibraryRefreshFailurePreservesSnapshot() async {
        let state = GenreLibraryState()
        let requestedScope = scope("account-a")
        await state.load(scope: requestedScope) { _ in
            GenrePage(genres: [genre("kept", "Kept")], hasMore: false, nextStartIndex: 1)
        }

        await state.refresh(scope: requestedScope) { _ in throw GenreSyntheticError.failed }

        XCTAssertEqual(state.genres.map(\.id), ["kept"])
        XCTAssertNotNil(state.errorMessage)
    }

    func testLibraryScopeChangeRejectsStaleResponse() async {
        let state = GenreLibraryState()
        let gate = GenrePageGate()
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

        await gate.resume("new", with: GenrePage(
            genres: [genre("new", "New")], hasMore: false, nextStartIndex: 1
        ))
        await newTask.value
        await gate.resume("old", with: GenrePage(
            genres: [genre("private-old", "Old")], hasMore: false, nextStartIndex: 1
        ))
        await oldTask.value

        XCTAssertEqual(state.genres.map(\.id), ["new"])
    }

    func testDetailPaginatesAlbumsAndTracksWithIndependentCursors() async {
        let state = GenreDetailState()
        let requestedScope = scope("account-a")
        let selectedGenre = genre("rock", "Rock")
        await state.load(genre: selectedGenre, scope: requestedScope) { _ in
            AlbumPage(albums: [album("a1")], hasMore: true, nextStartIndex: 10)
        } loadTracks: { _ in
            GenreTrackPage(
                occurrences: [occurrence("o1", trackID: "t1")],
                hasMore: true,
                nextStartIndex: 20
            )
        }

        await state.loadMoreAlbums(genre: selectedGenre, scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 10)
            return AlbumPage(
                albums: [album("a1"), album("a2")],
                hasMore: false,
                nextStartIndex: 12
            )
        }
        await state.loadMoreTracks(genre: selectedGenre, scope: requestedScope) { startIndex in
            XCTAssertEqual(startIndex, 20)
            return GenreTrackPage(
                occurrences: [occurrence("o2", trackID: "t2")],
                hasMore: false,
                nextStartIndex: 21
            )
        }

        XCTAssertEqual(state.albums.map(\.id), ["a1", "a2"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["o1", "o2"])
    }

    func testDetailNeverCollapsesRepeatedTrackOccurrences() async {
        let state = GenreDetailState()
        let requestedScope = scope("account-a")
        let selectedGenre = genre("rock", "Rock")

        await state.load(genre: selectedGenre, scope: requestedScope) { _ in
            AlbumPage(albums: [], hasMore: false, nextStartIndex: 0)
        } loadTracks: { _ in
            GenreTrackPage(
                occurrences: [occurrence("o1", trackID: "same"), occurrence("o2", trackID: "same")],
                hasMore: true,
                nextStartIndex: 2
            )
        }
        await state.loadMoreTracks(genre: selectedGenre, scope: requestedScope) { _ in
            GenreTrackPage(
                occurrences: [occurrence("o3", trackID: "same"), occurrence("o4", trackID: "last")],
                hasMore: false,
                nextStartIndex: 4
            )
        }

        XCTAssertEqual(state.trackOccurrences.map(\.id), ["o1", "o2", "o3", "o4"])
        XCTAssertEqual(state.trackOccurrences.map(\.track.id), ["same", "same", "same", "last"])
    }

    func testDetailPaginationFailuresPreserveBothSnapshotsAndRetryability() async {
        let state = GenreDetailState()
        let requestedScope = scope("account-a")
        let selectedGenre = genre("rock", "Rock")
        await state.load(genre: selectedGenre, scope: requestedScope) { _ in
            AlbumPage(albums: [album("kept-album")], hasMore: true, nextStartIndex: 1)
        } loadTracks: { _ in
            GenreTrackPage(
                occurrences: [occurrence("kept-occurrence", trackID: "kept-track")],
                hasMore: true,
                nextStartIndex: 1
            )
        }

        await state.loadMoreAlbums(genre: selectedGenre, scope: requestedScope) { _ in
            throw GenreSyntheticError.failed
        }
        await state.loadMoreTracks(genre: selectedGenre, scope: requestedScope) { _ in
            throw GenreSyntheticError.failed
        }

        XCTAssertEqual(state.albums.map(\.id), ["kept-album"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["kept-occurrence"])
        XCTAssertNotNil(state.albumPaginationError)
        XCTAssertNotNil(state.trackPaginationError)
        XCTAssertTrue(state.canLoadMoreAlbums)
        XCTAssertTrue(state.canLoadMoreTracks)
    }

    func testDetailRefreshFailuresPreserveValidSnapshots() async {
        let state = GenreDetailState()
        let requestedScope = scope("account-a")
        let selectedGenre = genre("rock", "Rock")
        await state.load(genre: selectedGenre, scope: requestedScope) { _ in
            AlbumPage(albums: [album("kept-album")], hasMore: false, nextStartIndex: 1)
        } loadTracks: { _ in
            GenreTrackPage(
                occurrences: [occurrence("kept-occurrence", trackID: "kept-track")],
                hasMore: false,
                nextStartIndex: 1
            )
        }

        await state.refresh(genre: selectedGenre, scope: requestedScope) { _ in
            throw GenreSyntheticError.failed
        } loadTracks: { _ in
            throw GenreSyntheticError.failed
        }

        XCTAssertEqual(state.albums.map(\.id), ["kept-album"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["kept-occurrence"])
        XCTAssertNotNil(state.albumErrorMessage)
        XCTAssertNotNil(state.trackErrorMessage)
    }

    func testDetailGenreChangeRejectsPreviousGenreResponse() async {
        let state = GenreDetailState()
        let requestedScope = scope("account-a")
        let oldGenre = genre("old", "Old")
        let newGenre = genre("new", "New")
        let albumGate = AlbumPageGate()

        let oldTask = Task {
            await state.load(genre: oldGenre, scope: requestedScope) { _ in
                try await albumGate.wait(for: "old")
            } loadTracks: { _ in
                XCTFail("A stale request must not advance to tracks")
                return GenreTrackPage(occurrences: [], hasMore: false, nextStartIndex: 0)
            }
        }
        await albumGate.waitUntilRegistered("old")
        let newTask = Task {
            await state.load(genre: newGenre, scope: requestedScope) { _ in
                try await albumGate.wait(for: "new")
            } loadTracks: { _ in
                GenreTrackPage(
                    occurrences: [occurrence("new-occurrence", trackID: "new-track")],
                    hasMore: false,
                    nextStartIndex: 1
                )
            }
        }
        await albumGate.waitUntilRegistered("new")

        await albumGate.resume("new", with: AlbumPage(
            albums: [album("new-album")], hasMore: false, nextStartIndex: 1
        ))
        await newTask.value
        await albumGate.resume("old", with: AlbumPage(
            albums: [album("private-old")], hasMore: false, nextStartIndex: 1
        ))
        await oldTask.value

        XCTAssertEqual(state.albums.map(\.id), ["new-album"])
        XCTAssertEqual(state.trackOccurrences.map(\.id), ["new-occurrence"])
    }

    private func scope(_ account: String) -> GenreFeatureScope {
        GenreFeatureScope(serverID: "server", accountID: account, libraryID: "music")
    }

    private func genre(_ id: String, _ name: String) -> Genre {
        Genre(id: id, name: name, imageTag: nil, itemCount: nil, albumCount: nil)
    }

    private func album(_ id: String) -> Album {
        Album(id: id, name: "Album \(id)", artist: "Artist", productionYear: nil, imageTag: nil)
    }

    private func occurrence(_ id: String, trackID: String) -> GenreTrackOccurrence {
        GenreTrackOccurrence(id: id, track: Track(
            id: trackID,
            name: "Track \(trackID)",
            artist: "Artist",
            album: "Album",
            index: nil,
            disc: nil,
            durationTicks: 30_000_000
        ))
    }
}

private enum GenreSyntheticError: Error {
    case failed
}

private actor GenrePageGate {
    private var continuations: [String: CheckedContinuation<GenrePage, Error>] = [:]

    func wait(for key: String) async throws -> GenrePage {
        try await withCheckedThrowingContinuation { continuations[key] = $0 }
    }

    func waitUntilRegistered(_ key: String) async {
        while continuations[key] == nil { await Task.yield() }
    }

    func resume(_ key: String, with page: GenrePage) {
        continuations.removeValue(forKey: key)?.resume(returning: page)
    }
}

private actor AlbumPageGate {
    private var continuations: [String: CheckedContinuation<AlbumPage, Error>] = [:]

    func wait(for key: String) async throws -> AlbumPage {
        try await withCheckedThrowingContinuation { continuations[key] = $0 }
    }

    func waitUntilRegistered(_ key: String) async {
        while continuations[key] == nil { await Task.yield() }
    }

    func resume(_ key: String, with page: AlbumPage) {
        continuations.removeValue(forKey: key)?.resume(returning: page)
    }
}
