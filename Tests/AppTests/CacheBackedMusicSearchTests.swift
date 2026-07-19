import XCTest
@testable import Jellytone

@MainActor
final class CacheBackedMusicSearchTests: XCTestCase {
    func testAlbumRefreshPresentsReopenedCacheBeforeRequestingServer() async throws {
        let cached = page(prefix: "cached").albums
        let store = SearchStore(cached: page(prefix: "cached"))
        var presentations: [[Album]] = []
        let refreshed = AlbumPage(
            albums: page(prefix: "server").albums,
            hasMore: true,
            nextStartIndex: 100
        )

        let result = try await CacheFirstAlbumRefresh.execute(
            scope: LibraryScope(serverID: "server-a", accountID: "account-a"),
            libraryID: "library-a",
            store: store,
            present: { presentations.append($0) }
        ) {
            XCTAssertEqual(presentations, [cached])
            return refreshed
        }

        XCTAssertEqual(result, refreshed)
        XCTAssertEqual(presentations, [cached, refreshed.albums])
    }

    func testOfflineFirstPageReturnsCacheOnlyResults() async throws {
        let store = SearchStore(cached: page(prefix: "cached"))

        let result = try await CacheBackedMusicSearch.execute(
            query: "synthetic", startIndex: 0,
            scope: LibraryScope(serverID: "server-a", accountID: "account-a"),
            libraryID: "library-a", store: store
        ) {
            throw URLError(.notConnectedToInternet)
        }

        XCTAssertEqual(result, page(prefix: "cached"))
        let searchCount = await store.searchCount
        XCTAssertEqual(searchCount, 1)
    }

    func testServerRefreshMergesAndPersistsDomainMetadata() async throws {
        let store = SearchStore(cached: page(prefix: "cached"))
        let server = MusicSearchPage(
            artists: [Artist(id: "cached-artist", name: "Refreshed", imageTag: nil)],
            albums: [Album(id: "server-album", name: "Server", artist: "Synthetic",
                           productionYear: nil, imageTag: nil)],
            hasMore: true,
            nextStartIndex: 40
        )

        let result = try await CacheBackedMusicSearch.execute(
            query: "synthetic", startIndex: 0,
            scope: LibraryScope(serverID: "server-a", accountID: "account-a"),
            libraryID: "library-a", store: store
        ) { server }

        XCTAssertEqual(result.artists.map(\.name), ["Refreshed"])
        XCTAssertEqual(result.albums.map(\.id), ["cached-album", "server-album"])
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.nextStartIndex, 40)
        let storedArtists = await store.storedArtists
        let storedAlbums = await store.storedAlbums
        XCTAssertEqual(storedArtists, server.artists)
        XCTAssertEqual(storedAlbums, server.albums)
    }

    func testAuthenticationFailureIsNotHiddenByCache() async {
        let store = SearchStore(cached: page(prefix: "cached"))

        do {
            _ = try await CacheBackedMusicSearch.execute(
                query: "synthetic", startIndex: 0,
                scope: LibraryScope(serverID: "server-a", accountID: "account-a"),
                libraryID: "library-a", store: store
            ) { throw APIError.httpStatus(401) }
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? APIError, .httpStatus(401))
        }
    }

    func testLaterServerPageDoesNotPrependCachedResults() async throws {
        let store = SearchStore(cached: page(prefix: "cached"))
        let server = page(prefix: "page-two")

        let result = try await CacheBackedMusicSearch.execute(
            query: "synthetic", startIndex: 40,
            scope: LibraryScope(serverID: "server-a", accountID: "account-a"),
            libraryID: "library-a", store: store
        ) { server }

        XCTAssertEqual(result, server)
        let searchCount = await store.searchCount
        XCTAssertEqual(searchCount, 0)
    }

    private func page(prefix: String) -> MusicSearchPage {
        MusicSearchPage(
            artists: [Artist(id: "\(prefix)-artist", name: "Synthetic Artist", imageTag: nil)],
            albums: [Album(id: "\(prefix)-album", name: "Synthetic Album", artist: "Synthetic Artist",
                           productionYear: nil, imageTag: nil)],
            hasMore: false,
            nextStartIndex: 0
        )
    }
}

private actor SearchStore: LibraryStoring {
    let cached: MusicSearchPage
    private(set) var searchCount = 0
    private(set) var storedArtists: [Artist] = []
    private(set) var storedAlbums: [Album] = []

    init(cached: MusicSearchPage) { self.cached = cached }

    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album] { cached.albums }
    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws {}
    func cachedHomeShelfSnapshot(
        scope: LibraryScope, libraryID: String?
    ) async throws -> HomeShelfSnapshot? { nil }
    func replaceHomeShelfSnapshot(
        _ snapshot: HomeShelfSnapshot, scope: LibraryScope, libraryID: String?
    ) async throws {}

    func storeSearchMetadata(
        artists: [Artist], albums: [Album], scope: LibraryScope, libraryID: String?
    ) async throws {
        storedArtists = artists
        storedAlbums = albums
    }

    func searchMusic(
        query: String, scope: LibraryScope, libraryID: String?
    ) async throws -> MusicSearchPage {
        searchCount += 1
        return cached
    }
}
