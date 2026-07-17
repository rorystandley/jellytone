import XCTest
@testable import JellyfinAudio

final class TrackCatalogTests: XCTestCase {
    private func track(_ id: String, _ name: String, artist: String = "Artist") -> Track {
        Track(id: id, name: name, artist: artist, album: "Album", index: nil, disc: nil, durationTicks: nil)
    }

    func testOrderingUsesNormalizedTitleThenArtistAlbumAndStableIdentity() {
        let values = [
            TrackCatalogOccurrence(id: "2", track: track("id-b", "Café", artist: "B"), ordinal: 1),
            TrackCatalogOccurrence(id: "1", track: track("id-a", "Café", artist: "A"), ordinal: 0),
            TrackCatalogOccurrence(id: "3", track: track("id-c", "Same", artist: "A"), ordinal: 2),
            TrackCatalogOccurrence(id: "4", track: track("id-d", "Same", artist: "A"), ordinal: 3),
        ].sorted(by: TrackCatalogOrdering.precedes)
        XCTAssertEqual(values.map { $0.track.id }, ["id-a", "id-b", "id-c", "id-d"])
    }

    @MainActor
    func testPaginationMergesOverlappingPagesWithoutDroppingOccurrencesAndRetainsOnFailure() async {
        let state = TrackCatalogState()
        let scope = TrackCatalogScope(serverID: "server", accountID: "account", libraryID: "library")
        let first = TrackCatalogPage(occurrences: [
            TrackCatalogOccurrence(id: "occ-0", track: track("same", "A"), ordinal: 0),
            TrackCatalogOccurrence(id: "occ-1", track: track("same", "A"), ordinal: 1),
        ], hasMore: true, nextStartIndex: 2)
        await state.refresh(scope: scope) { _ in first }
        await state.loadMore(scope: scope) { _ in
            TrackCatalogPage(occurrences: [first.occurrences[1], TrackCatalogOccurrence(id: "occ-2", track: self.track("later", "B"), ordinal: 2)], hasMore: false, nextStartIndex: 4)
        }
        XCTAssertEqual(state.occurrences.map(\.id), ["occ-0", "occ-1", "occ-2"])
        await state.loadMore(scope: scope) { _ in throw APIError.httpStatus(503) }
        XCTAssertEqual(state.occurrences.count, 3)
        XCTAssertNil(state.errorMessage)
    }

    @MainActor
    func testEmptyFirstPageIsLoadedAsAnHonestEmptyCatalog() async {
        let state = TrackCatalogState()
        let scope = TrackCatalogScope(serverID: "server", accountID: "account", libraryID: "library")
        await state.refresh(scope: scope) { _ in TrackCatalogPage(occurrences: [], hasMore: false, nextStartIndex: 0) }
        XCTAssertTrue(state.hasLoaded)
        XCTAssertTrue(state.occurrences.isEmpty)
        XCTAssertFalse(state.hasMore)
        XCTAssertNil(state.errorMessage)
    }

    func testTrackCatalogCacheIsScopedAndFirstPageIsBounded() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("track-catalog-\(UUID().uuidString).sqlite")
        let store = try SQLiteLibraryStore(databaseURL: url)
        let scope = LibraryScope(serverID: "server", accountID: "account")
        let page = TrackCatalogPage(occurrences: (0..<4).map { index in
            TrackCatalogOccurrence(id: "occ-\(index)", track: track("id-\(index)", "Track \(index)"), ordinal: index)
        }, hasMore: true, nextStartIndex: 4)
        try await store.replaceTrackCatalogPage(page, generation: "generation-a", scope: scope, libraryID: "library-a")
        let cached = try await store.cachedTrackCatalogPage(scope: scope, libraryID: "library-a", limit: 2)
        XCTAssertEqual(cached?.occurrences.map(\.id), ["occ-0", "occ-1"])
        let otherLibrary = try await store.cachedTrackCatalogPage(scope: scope, libraryID: "library-b", limit: 10)
        XCTAssertNil(otherLibrary)
    }
}
