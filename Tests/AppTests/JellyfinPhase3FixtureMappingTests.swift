import Foundation
import XCTest
@testable import Jellytone

final class JellyfinPhase3FixtureMappingTests: XCTestCase {
    override func tearDown() {
        Phase3FixtureURLProtocol.handler = nil
        super.tearDown()
    }

    func testAlbumsMapCompilationDuplicateUnicodeAndFallbackMetadataFromFixture() async throws {
        let api = try makeAPI(fixture: "albums")

        let page = try await api.albums(userID: "synthetic-account-a", libraryID: "synthetic-library")

        XCTAssertEqual(
            page.albums.map(\.id),
            [
                "album-compilation-001", "album-duplicate-a", "album-duplicate-b",
                "album-unicode-composed", "album-unicode-decomposed", "album-minimal",
                "album-malformed-optionals",
            ]
        )
        XCTAssertEqual(page.albums.first?.artist, "Various Artists")
        XCTAssertEqual(page.albums.first?.artistID, "artist-various",
                       "Compilations must open the album artist, not a featured soloist")
        XCTAssertEqual(page.albums.first { $0.id == "album-duplicate-a" }?.artistID, "artist-duplicate")
        XCTAssertEqual(page.albums.first { $0.id == "album-unicode-composed" }?.artistID, "artist-zoe")
        XCTAssertEqual(page.albums.first { $0.id == "album-unicode-decomposed" }?.artistID, "artist-angstrom")
        XCTAssertEqual(page.albums.filter { $0.name == "Shared Display Name" }.map(\.id),
                       ["album-duplicate-a", "album-duplicate-b"])
        XCTAssertEqual(page.albums.first { $0.id == "album-unicode-composed" }?.name, "Café 東京 🎧")
        XCTAssertEqual(page.albums.first { $0.id == "album-unicode-decomposed" }?.name,
                       "Cafe\u{301} Sessions")

        let minimal = try XCTUnwrap(page.albums.first { $0.id == "album-minimal" })
        XCTAssertEqual(minimal.artist, "Unknown Artist")
        XCTAssertNil(minimal.artistID)
        XCTAssertNil(minimal.productionYear)
        XCTAssertNil(minimal.imageTag)

        let damaged = try XCTUnwrap(page.albums.first { $0.id == "album-malformed-optionals" })
        XCTAssertEqual(damaged.artist, "Unknown Artist")
        XCTAssertNil(damaged.artistID)
        XCTAssertNil(damaged.productionYear)
        XCTAssertNil(damaged.imageTag)
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.nextStartIndex, 11, "Rejected records must still advance server pagination")
    }

    func testAlbumsBrowseRequestsAlbumArtistIdentityFields() async throws {
        let api = try makeAPI(fixture: "albums")
        Phase3FixtureURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertTrue(components.queryItems?.contains(where: {
                $0.name == "Fields"
                    && ($0.value?.contains("AlbumArtists") == true)
                    && ($0.value?.contains("AlbumArtist") == true)
            }) == true)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, Data(#"{"Items":[],"TotalRecordCount":0}"#.utf8))
        }

        _ = try await api.albums(userID: "account", libraryID: "library")
    }

    func testAlbumsPreferMatchingAlbumArtistsOverFeaturedArtistItems() async throws {
        let api = try makeAPI(fixture: "albums")
        Phase3FixtureURLProtocol.handler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let json = #"""
            {"Items":[
                {"Id":"album-various","Name":"Sampler","Type":"MusicAlbum",
                 "AlbumArtist":"Various Artists",
                 "AlbumArtists":[{"Name":"Various Artists","Id":"artist-various"}],
                 "Artists":["Featured Soloist"],
                 "ArtistItems":[{"Name":"Featured Soloist","Id":"artist-featured"}]},
                {"Id":"album-legacy","Name":"Legacy","Type":"MusicAlbum",
                 "AlbumArtist":"Legacy Artist",
                 "ArtistIds":["artist-legacy-only"]}
            ],"TotalRecordCount":2}
            """#
            return (response, Data(json.utf8))
        }

        let page = try await api.albums(userID: "account", libraryID: nil)
        let various = try XCTUnwrap(page.albums.first { $0.id == "album-various" })
        let legacy = try XCTUnwrap(page.albums.first { $0.id == "album-legacy" })

        XCTAssertEqual(various.artist, "Various Artists")
        XCTAssertEqual(various.artistID, "artist-various")
        XCTAssertEqual(various.artistDestination?.id, "artist-various")
        XCTAssertEqual(legacy.artistID, "artist-legacy-only")
        XCTAssertEqual(legacy.artistDestination?.name, "Legacy Artist")
    }

    func testTracksPreferMatchingArtistItemsOverAlbumArtistsAndLegacyArtistIds() async throws {
        let api = try makeAPI(fixture: "tracks")
        Phase3FixtureURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertTrue(components.queryItems?.contains(where: {
                $0.name == "Fields" && ($0.value?.contains("AlbumId") == true)
            }) == true)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let json = #"""
            {"Items":[
                {"Id":"track-match","Name":"Match","Type":"Audio","Artists":["Track Artist"],
                 "ArtistItems":[{"Name":"Other","Id":"artist-other"},{"Name":"Track Artist","Id":"artist-track"}],
                 "AlbumArtists":[{"Name":"Album Artist","Id":"artist-album"}],
                 "ArtistIds":["artist-legacy"],
                 "Album":"Record","AlbumId":"album-record"},
                {"Id":"track-legacy","Name":"Legacy","Type":"Audio","Artists":["Legacy Artist"],
                 "ArtistIds":["artist-legacy-only"],
                 "Album":"Record","AlbumId":"album-record"}
            ]}
            """#
            return (response, Data(json.utf8))
        }

        let tracks = try await api.tracks(userID: "account", albumID: "album-record")
        let matched = try XCTUnwrap(tracks.first { $0.id == "track-match" })
        let legacy = try XCTUnwrap(tracks.first { $0.id == "track-legacy" })

        XCTAssertEqual(matched.artistID, "artist-track")
        XCTAssertEqual(matched.albumDestination?.id, "album-record")
        XCTAssertEqual(matched.artistDestination?.id, "artist-track")
        XCTAssertEqual(legacy.artistID, "artist-legacy-only")
        XCTAssertEqual(legacy.artistDestination?.name, "Legacy Artist")
    }

    func testSearchRetainsStableDistinctIdentitiesAndMalformedSiblingsFromFixture() async throws {
        let api = try makeAPI(fixture: "search")

        let first = try await api.searchMusic(
            userID: "synthetic-account-a",
            libraryID: "synthetic-library",
            query: "Cafe\u{301}"
        )

        XCTAssertEqual(first.artists.filter { $0.name == "Same Artist" }.map(\.id),
                       ["artist-duplicate-a", "artist-duplicate-b"])
        XCTAssertEqual(first.albums.filter { $0.name == "Same Album" }.map(\.id),
                       ["album-search-a", "album-search-b"])
        XCTAssertEqual(first.artists.first { $0.id == "artist-unicode" }?.name, "Mélodie Synth 東京")
        XCTAssertEqual(first.albums.first { $0.id == "album-search-unicode" }?.name, "Cafe\u{301} 🎶")

        let malformed = try XCTUnwrap(first.albums.first { $0.id == "album-search-malformed" })
        XCTAssertNil(malformed.productionYear)
        XCTAssertNil(malformed.imageTag)
        XCTAssertEqual(malformed.artist, "Unknown Artist")
        XCTAssertEqual(first.nextStartIndex, 9)
        XCTAssertFalse(first.hasMore)

        let second = try await api.searchMusic(
            userID: "synthetic-account-b",
            libraryID: "synthetic-library",
            query: "Cafe\u{301}"
        )
        XCTAssertEqual(second.artists.map(\.id), first.artists.map(\.id))
        XCTAssertEqual(second.albums.map(\.id), first.albums.map(\.id))
    }

    func testTracksUseCompilationArtistAndDeterministicDiscTrackOrderingFromFixture() async throws {
        let api = try makeAPI(fixture: "tracks")

        let tracks = try await api.tracks(userID: "synthetic-account-a", albumID: "album-multidisc")

        XCTAssertEqual(
            tracks.map(\.id),
            [
                "track-disc-1-01-a", "track-disc-1-01-b", "track-disc-1-02",
                "track-disc-2-01", "track-disc-2-02", "track-missing-index-a",
                "track-malformed-optionals", "track-missing-index-b",
            ]
        )
        XCTAssertEqual(tracks.first { $0.id == "track-disc-1-02" }?.artist, "Track Artist")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-1-02" }?.artistID, "artist-track")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-1-02" }?.albumID, "album-compilation-001")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-1-01-a" }?.artist, "Compilation Soloist")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-1-01-a" }?.artistID, "artist-compilation-soloist")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-2-01" }?.artist, "Album Artist")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-2-01" }?.artistID, "artist-album")
        XCTAssertEqual(tracks.first { $0.id == "track-disc-2-02" }?.artistID, "artist-disc")

        let unicode = try XCTUnwrap(tracks.first { $0.id == "track-missing-index-a" })
        XCTAssertEqual(unicode.name, "Cafe\u{301} Unnumbered")
        XCTAssertEqual(unicode.artist, "Unicode Fallback")
        XCTAssertNil(unicode.durationTicks)
        XCTAssertEqual(unicode.artistID, "artist-unicode-fallback")

        let malformed = try XCTUnwrap(tracks.first { $0.id == "track-malformed-optionals" })
        XCTAssertEqual(malformed.artist, "Unknown Artist")
        XCTAssertEqual(malformed.album, "")
        XCTAssertNil(malformed.albumID)
        XCTAssertNil(malformed.artistID)
        XCTAssertNil(malformed.disc)
        XCTAssertNil(malformed.index)
        XCTAssertNil(malformed.durationTicks)
    }

    private func makeAPI(fixture: String) throws -> JellyfinAPI {
        let data = try fixtureData(named: fixture)
        Phase3FixtureURLProtocol.handler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Phase3FixtureURLProtocol.self]
        return JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid/jellyfin")),
            deviceID: "synthetic-device",
            token: "synthetic-token",
            urlSession: URLSession(configuration: configuration)
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: fixtureURL)
    }
}

private final class Phase3FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
