import XCTest
@testable import Jellytone

final class MusicSearchResultMergerTests: XCTestCase {
    func testMergesCacheFirstAndReplacesDuplicateMetadataInPlace() {
        let cached = page(
            artists: [artist("cached-first", "First"), artist("shared", "Cached Name")],
            albums: [album("cached-album", "Cached First"), album("shared-album", "Cached Album")]
        )
        let server = page(
            artists: [artist("shared", "Fresh Name"), artist("server-last", "Last")],
            albums: [album("shared-album", "Fresh Album"), album("server-album", "Server Last")],
            hasMore: true,
            nextStartIndex: 25
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(merged.artists.map(\.id), ["cached-first", "shared", "server-last"])
        XCTAssertEqual(merged.artists.map(\.name), ["First", "Fresh Name", "Last"])
        XCTAssertEqual(merged.albums.map(\.id), ["cached-album", "shared-album", "server-album"])
        XCTAssertEqual(merged.albums.map(\.name), ["Cached First", "Fresh Album", "Server Last"])
    }

    func testEliminatesRepeatedIDsWithinEachSource() {
        let cached = page(
            artists: [artist("same", "First Cached"), artist("same", "Ignored Cached")],
            albums: [album("same", "First Cached"), album("same", "Ignored Cached")]
        )
        let server = page(
            artists: [artist("same", "First Server"), artist("same", "Ignored Server")],
            albums: [album("same", "First Server"), album("same", "Ignored Server")]
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(merged.artists, [artist("same", "First Server")])
        XCTAssertEqual(merged.albums, [album("same", "First Server")])
    }

    func testPreservesSourceOrderWithoutLocaleDependentSorting() {
        let cached = page(
            artists: [artist("z", "Zulu"), artist("a", "Alpha")],
            albums: [album("z", "Zulu"), album("a", "Alpha")]
        )
        let server = page(
            artists: [artist("n", "November"), artist("b", "Bravo")],
            albums: [album("n", "November"), album("b", "Bravo")]
        )

        let first = MusicSearchResultMerger.merge(cached: cached, server: server)
        let second = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.artists.map(\.id), ["z", "a", "n", "b"])
        XCTAssertEqual(first.albums.map(\.id), ["z", "a", "n", "b"])
    }

    func testIdentityDoesNotCollapseNamesThatDifferOnlyByCaseOrUnicodeRepresentation() {
        let composed = "Björk"
        let decomposed = "Bjo\u{308}rk"
        let cached = page(
            artists: [artist("artist-upper", composed)],
            albums: [album("album-upper", "DEBUT")]
        )
        let server = page(
            artists: [artist("artist-lower", decomposed)],
            albums: [album("album-lower", "debut")]
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(merged.artists.map(\.id), ["artist-upper", "artist-lower"])
        XCTAssertEqual(merged.albums.map(\.id), ["album-upper", "album-lower"])
    }

    func testSupportsCacheOnlyResults() {
        let cached = page(
            artists: [artist("cached", "Cached")],
            albums: [album("cached", "Cached")]
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: page())

        XCTAssertEqual(merged.artists, cached.artists)
        XCTAssertEqual(merged.albums, cached.albums)
        XCTAssertFalse(merged.hasMore)
        XCTAssertEqual(merged.nextStartIndex, 0)
    }

    func testSupportsServerOnlyResults() {
        let server = page(
            artists: [artist("server", "Server")],
            albums: [album("server", "Server")],
            hasMore: true,
            nextStartIndex: 50
        )

        let merged = MusicSearchResultMerger.merge(cached: page(), server: server)

        XCTAssertEqual(merged, server)
    }

    func testServerPaginationMetadataIsUnaffectedByCachedResultCount() {
        let cached = page(
            artists: (0..<12).map { artist("cached-artist-\($0)", "Artist \($0)") },
            albums: (0..<9).map { album("cached-album-\($0)", "Album \($0)") },
            hasMore: false,
            nextStartIndex: 999
        )
        let server = page(
            artists: [artist("server", "Server")],
            albums: [album("server", "Server")],
            hasMore: true,
            nextStartIndex: 25
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertTrue(merged.hasMore)
        XCTAssertEqual(merged.nextStartIndex, 25)
    }

    private func page(
        artists: [Artist] = [],
        albums: [Album] = [],
        hasMore: Bool = false,
        nextStartIndex: Int = 0
    ) -> MusicSearchPage {
        MusicSearchPage(
            artists: artists,
            albums: albums,
            hasMore: hasMore,
            nextStartIndex: nextStartIndex
        )
    }

    private func artist(_ id: String, _ name: String) -> Artist {
        Artist(id: id, name: name, imageTag: nil)
    }

    private func album(_ id: String, _ name: String) -> Album {
        Album(id: id, name: name, artist: "Synthetic Artist", productionYear: nil, imageTag: nil)
    }
}
