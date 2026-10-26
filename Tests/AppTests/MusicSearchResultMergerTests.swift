import XCTest
@testable import Jellytone

final class MusicSearchResultMergerTests: XCTestCase {
    func testMergesCacheFirstAndReplacesDuplicateMetadataInPlace() {
        let cached = page(
            artists: [artist("cached-first", "First"), artist("shared", "Cached Name")],
            albums: [album("cached-album", "Cached First"), album("shared-album", "Cached Album")],
            tracks: [track("cached-track", "Cached Track"), track("shared-track", "Cached Song")],
            playlists: [playlist("cached-pl", "Cached Mix"), playlist("shared-pl", "Cached List")]
        )
        let server = page(
            artists: [artist("shared", "Fresh Name"), artist("server-last", "Last")],
            albums: [album("shared-album", "Fresh Album"), album("server-album", "Server Last")],
            tracks: [track("shared-track", "Fresh Song"), track("server-track", "Server Track")],
            playlists: [playlist("shared-pl", "Fresh List"), playlist("server-pl", "Server Mix")],
            hasMore: true,
            nextStartIndex: 25
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(merged.artists.map(\.id), ["cached-first", "shared", "server-last"])
        XCTAssertEqual(merged.artists.map(\.name), ["First", "Fresh Name", "Last"])
        XCTAssertEqual(merged.albums.map(\.id), ["cached-album", "shared-album", "server-album"])
        XCTAssertEqual(merged.albums.map(\.name), ["Cached First", "Fresh Album", "Server Last"])
        XCTAssertEqual(merged.tracks.map(\.id), ["cached-track", "shared-track", "server-track"])
        XCTAssertEqual(merged.tracks.map(\.name), ["Cached Track", "Fresh Song", "Server Track"])
        XCTAssertEqual(merged.playlists.map(\.id), ["cached-pl", "shared-pl", "server-pl"])
        XCTAssertEqual(merged.playlists.map(\.name), ["Cached Mix", "Fresh List", "Server Mix"])
    }

    func testEliminatesRepeatedIDsWithinEachSource() {
        let cached = page(
            artists: [artist("same", "First Cached"), artist("same", "Ignored Cached")],
            albums: [album("same", "First Cached"), album("same", "Ignored Cached")],
            tracks: [track("same", "First Cached"), track("same", "Ignored Cached")],
            playlists: [playlist("same", "First Cached"), playlist("same", "Ignored Cached")]
        )
        let server = page(
            artists: [artist("same", "First Server"), artist("same", "Ignored Server")],
            albums: [album("same", "First Server"), album("same", "Ignored Server")],
            tracks: [track("same", "First Server"), track("same", "Ignored Server")],
            playlists: [playlist("same", "First Server"), playlist("same", "Ignored Server")]
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(merged.artists, [artist("same", "First Server")])
        XCTAssertEqual(merged.albums, [album("same", "First Server")])
        XCTAssertEqual(merged.tracks, [track("same", "First Server")])
        XCTAssertEqual(merged.playlists, [playlist("same", "First Server")])
    }

    func testPreservesSourceOrderWithoutLocaleDependentSorting() {
        let cached = page(
            artists: [artist("z", "Zulu"), artist("a", "Alpha")],
            albums: [album("z", "Zulu"), album("a", "Alpha")],
            tracks: [track("z", "Zulu"), track("a", "Alpha")],
            playlists: [playlist("z", "Zulu"), playlist("a", "Alpha")]
        )
        let server = page(
            artists: [artist("n", "November"), artist("b", "Bravo")],
            albums: [album("n", "November"), album("b", "Bravo")],
            tracks: [track("n", "November"), track("b", "Bravo")],
            playlists: [playlist("n", "November"), playlist("b", "Bravo")]
        )

        let first = MusicSearchResultMerger.merge(cached: cached, server: server)
        let second = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.artists.map(\.id), ["z", "a", "n", "b"])
        XCTAssertEqual(first.albums.map(\.id), ["z", "a", "n", "b"])
        XCTAssertEqual(first.tracks.map(\.id), ["z", "a", "n", "b"])
        XCTAssertEqual(first.playlists.map(\.id), ["z", "a", "n", "b"])
    }

    func testIdentityDoesNotCollapseNamesThatDifferOnlyByCaseOrUnicodeRepresentation() {
        let composed = "Björk"
        let decomposed = "Bjo\u{308}rk"
        let cached = page(
            artists: [artist("artist-upper", composed)],
            albums: [album("album-upper", "DEBUT")],
            tracks: [track("track-upper", "SONG")],
            playlists: [playlist("pl-upper", "MIX")]
        )
        let server = page(
            artists: [artist("artist-lower", decomposed)],
            albums: [album("album-lower", "debut")],
            tracks: [track("track-lower", "song")],
            playlists: [playlist("pl-lower", "mix")]
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: server)

        XCTAssertEqual(merged.artists.map(\.id), ["artist-upper", "artist-lower"])
        XCTAssertEqual(merged.albums.map(\.id), ["album-upper", "album-lower"])
        XCTAssertEqual(merged.tracks.map(\.id), ["track-upper", "track-lower"])
        XCTAssertEqual(merged.playlists.map(\.id), ["pl-upper", "pl-lower"])
    }

    func testSupportsCacheOnlyResults() {
        let cached = page(
            artists: [artist("cached", "Cached")],
            albums: [album("cached", "Cached")],
            tracks: [track("cached", "Cached")],
            playlists: [playlist("cached", "Cached")]
        )

        let merged = MusicSearchResultMerger.merge(cached: cached, server: page())

        XCTAssertEqual(merged.artists, cached.artists)
        XCTAssertEqual(merged.albums, cached.albums)
        XCTAssertEqual(merged.tracks, cached.tracks)
        XCTAssertEqual(merged.playlists, cached.playlists)
        XCTAssertFalse(merged.hasMore)
        XCTAssertEqual(merged.nextStartIndex, 0)
    }

    func testSupportsServerOnlyResults() {
        let server = page(
            artists: [artist("server", "Server")],
            albums: [album("server", "Server")],
            tracks: [track("server", "Server")],
            playlists: [playlist("server", "Server")],
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
            tracks: (0..<5).map { track("cached-track-\($0)", "Track \($0)") },
            playlists: (0..<3).map { playlist("cached-pl-\($0)", "List \($0)") },
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
        tracks: [Track] = [],
        playlists: [Playlist] = [],
        hasMore: Bool = false,
        nextStartIndex: Int = 0
    ) -> MusicSearchPage {
        MusicSearchPage(
            artists: artists,
            albums: albums,
            tracks: tracks,
            playlists: playlists,
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

    private func track(_ id: String, _ name: String) -> Track {
        Track(id: id, name: name, artist: "Synthetic Artist", album: "Synthetic Album",
              index: 1, disc: 1, durationTicks: 600_000_000)
    }

    private func playlist(_ id: String, _ name: String) -> Playlist {
        Playlist(id: id, name: name, imageTag: nil, itemCount: 3)
    }
}
