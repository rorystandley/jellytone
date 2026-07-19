import Foundation
import XCTest
@testable import Jellytone

final class GenreGatewayTests: XCTestCase {
    override func tearDown() {
        GenreURLProtocol.handler = nil
        super.tearDown()
    }

    func testGenreFixturePreservesStableIdentityCountsUnicodeAndMalformedWirePagination() async throws {
        let api = try makeFixtureAPI(named: "genres")

        let page = try await api.genres(
            userID: "synthetic-user",
            libraryID: "synthetic-library",
            startIndex: 0,
            limit: 20
        )

        XCTAssertEqual(page.genres.map(\.id), [
            "genre-rock-a", "genre-rock-b", "genre-unicode",
            "genre-damaged-counts", "genre-legacy",
        ])
        XCTAssertEqual(page.genres.filter { $0.name == "Rock" }.map(\.id), [
            "genre-rock-a", "genre-rock-b",
        ])
        XCTAssertEqual(page.genres.first { $0.id == "genre-unicode" }?.name, "Cafe\u{301} 東京 🎧")
        XCTAssertEqual(page.genres.first { $0.id == "genre-rock-a" }?.imageTag, "genre-art-rock-a")
        XCTAssertEqual(page.genres.first { $0.id == "genre-rock-a" }?.itemCount, 12)
        XCTAssertEqual(page.genres.first { $0.id == "genre-rock-a" }?.albumCount, 3)
        XCTAssertEqual(page.genres.first { $0.id == "genre-rock-b" }?.itemCount, 7)
        XCTAssertEqual(page.genres.first { $0.id == "genre-unicode" }?.itemCount, 4)
        XCTAssertNil(page.genres.first { $0.id == "genre-damaged-counts" }?.itemCount)
        XCTAssertNil(page.genres.first { $0.id == "genre-damaged-counts" }?.albumCount)
        XCTAssertEqual(page.nextStartIndex, 9, "Every wire record must advance the cursor")
        XCTAssertFalse(page.hasMore)
    }

    func testGenreAlbumFixtureUsesStableGenreIdentityAndRejectsNonMusicRecords() async throws {
        let api = try makeFixtureAPI(named: "genre-albums")

        let page = try await api.genreAlbums(
            userID: "synthetic-user",
            genreID: "genre-rock-a",
            libraryID: "synthetic-library",
            startIndex: 10,
            limit: 20
        )

        XCTAssertEqual(page.albums.map(\.id), [
            "genre-album-a", "genre-album-b", "genre-album-unicode",
        ])
        XCTAssertEqual(page.albums.filter { $0.name == "Shared Album" }.map(\.id), [
            "genre-album-a", "genre-album-b",
        ])
        XCTAssertEqual(page.albums.first?.artist, "Various Artists")
        XCTAssertEqual(page.albums.first?.imageTag, "genre-album-art-a")
        let unicode = try XCTUnwrap(page.albums.first { $0.id == "genre-album-unicode" })
        XCTAssertEqual(unicode.name, "Café 東京")
        XCTAssertEqual(unicode.artist, "Unknown Artist")
        XCTAssertNil(unicode.productionYear)
        XCTAssertEqual(page.nextStartIndex, 16)
        XCTAssertFalse(page.hasMore)
    }

    func testGenreTrackFixturePreservesServerOrderDuplicateOccurrencesAndWireOffsets() async throws {
        let api = try makeFixtureAPI(named: "genre-tracks")

        let page = try await api.genreTracks(
            userID: "synthetic-user",
            genreID: "genre-rock-a",
            libraryID: "synthetic-library",
            startIndex: 20,
            limit: 20
        )

        XCTAssertEqual(page.occurrences.map(\.id), [
            "genre-rock-a:20:track-a",
            "genre-rock-a:22:track-duplicate",
            "genre-rock-a:23:track-duplicate",
            "genre-rock-a:26:track-unicode",
            "genre-rock-a:27:track-legacy",
        ])
        XCTAssertEqual(page.occurrences.map(\.track.id), [
            "track-a", "track-duplicate", "track-duplicate", "track-unicode", "track-legacy",
        ])
        XCTAssertNotEqual(page.occurrences[1].id, page.occurrences[2].id)
        XCTAssertEqual(page.occurrences[3].track.name, "Cafe\u{301} Finale 東京")
        XCTAssertEqual(page.occurrences[3].track.artist, "Unicode Artist")
        XCTAssertNil(page.occurrences[3].track.durationTicks)
        XCTAssertEqual(page.occurrences[4].track.artist, "Unknown Artist")
        XCTAssertEqual(page.occurrences[4].track.album, "")
        XCTAssertEqual(page.nextStartIndex, 28)
        XCTAssertFalse(page.hasMore)
    }

    func testGenreRequestsScopeByAccountLibraryStableIDAndMusicTypes() async throws {
        var requests: [URLRequest] = []
        GenreURLProtocol.handler = { request in
            requests.append(request)
            return Self.response(request, json: #"{"Items":[],"TotalRecordCount":0}"#)
        }
        let api = try makeAPI()

        _ = try await api.genres(
            userID: "user id",
            libraryID: "library/id",
            startIndex: 5,
            limit: 10
        )
        _ = try await api.genreAlbums(
            userID: "user id",
            genreID: "genre/id",
            libraryID: "library/id",
            startIndex: 15,
            limit: 20
        )
        _ = try await api.genreTracks(
            userID: "user id",
            genreID: "genre/id",
            libraryID: "library/id",
            startIndex: 25,
            limit: 30
        )

        XCTAssertEqual(requests.count, 3)
        try assertCommonScope(requests[0], path: "/reverse-proxy/Genres", itemType: nil)
        let genresQuery = try Self.query(requests[0])
        XCTAssertNil(genresQuery["GenreIds"])
        XCTAssertEqual(genresQuery["StartIndex"], "5")
        XCTAssertEqual(genresQuery["Limit"], "10")
        XCTAssertEqual(genresQuery["SortBy"], "SortName")

        try assertCommonScope(requests[1], path: "/reverse-proxy/Items", itemType: "MusicAlbum")
        let albumQuery = try Self.query(requests[1])
        XCTAssertEqual(albumQuery["GenreIds"], "genre/id")
        XCTAssertNil(albumQuery["Genres"], "Genre selection must never depend on a display name")
        XCTAssertEqual(albumQuery["StartIndex"], "15")
        XCTAssertEqual(albumQuery["Limit"], "20")

        try assertCommonScope(requests[2], path: "/reverse-proxy/Items", itemType: "Audio")
        let trackQuery = try Self.query(requests[2])
        XCTAssertEqual(trackQuery["GenreIds"], "genre/id")
        XCTAssertNil(trackQuery["Genres"], "Genre selection must never depend on a display name")
        XCTAssertEqual(trackQuery["StartIndex"], "25")
        XCTAssertEqual(trackQuery["Limit"], "30")
        XCTAssertEqual(trackQuery["SortBy"], "Album,ParentIndexNumber,IndexNumber,SortName")
    }

    func testGenrePaginationAdvancesByWireCountAndUsesTotalsWhenPresent() async throws {
        GenreURLProtocol.handler = { request in
            let start = try Self.query(request)["StartIndex"]
            if start == "0" {
                return Self.response(
                    request,
                    json: #"{"Items":[{"Id":"genre-a","Name":"A","Type":"MusicGenre"},17],"TotalRecordCount":3}"#
                )
            }
            XCTAssertEqual(start, "2")
            return Self.response(
                request,
                json: #"{"Items":[{"Id":"genre-b","Name":"B","Type":"MusicGenre"}],"TotalRecordCount":3}"#
            )
        }
        let api = try makeAPI()

        let first = try await api.genres(userID: "user", libraryID: "library", limit: 2)
        XCTAssertEqual(first.genres.map(\.id), ["genre-a"])
        XCTAssertEqual(first.nextStartIndex, 2)
        XCTAssertTrue(first.hasMore)
        let second = try await api.genres(
            userID: "user",
            libraryID: "library",
            startIndex: first.nextStartIndex,
            limit: 2
        )

        XCTAssertEqual((first.genres + second.genres).map(\.id), ["genre-a", "genre-b"])
        XCTAssertEqual(second.nextStartIndex, 3)
        XCTAssertFalse(second.hasMore)
    }

    func testGenreAuthenticationExpiryMalformedPayloadAndCancellationStayTyped() async throws {
        let api = try makeAPI()
        GenreURLProtocol.handler = { request in
            Self.response(request, status: 401, json: #"{"error":"expired"}"#)
        }
        do {
            _ = try await api.genreAlbums(
                userID: "user",
                genreID: "genre",
                libraryID: "library"
            )
            XCTFail("Expected authentication expiry")
        } catch {
            XCTAssertEqual(error as? APIError, .httpStatus(401))
        }

        GenreURLProtocol.handler = { request in
            Self.response(request, json: #"{"Items":{"not":"an-array"}}"#)
        }
        do {
            _ = try await api.genres(userID: "user", libraryID: "library")
            XCTFail("Expected malformed payload")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidPayload)
        }

        GenreURLProtocol.handler = { _ in throw URLError(.cancelled) }
        do {
            _ = try await api.genreTracks(
                userID: "user",
                genreID: "genre",
                libraryID: "library"
            )
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func assertCommonScope(_ request: URLRequest, path: String, itemType: String?) throws {
        let components = try XCTUnwrap(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        let query = try Self.query(request)
        XCTAssertEqual(components.path, path)
        XCTAssertEqual(query["userId"], "user id")
        XCTAssertEqual(query["ParentId"], "library/id")
        if let itemType {
            XCTAssertEqual(query["IncludeItemTypes"], itemType)
        } else {
            XCTAssertNil(query["IncludeItemTypes"])
        }
        XCTAssertEqual(query["Recursive"], "true")
        XCTAssertEqual(query["EnableTotalRecordCount"], "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-secret")
        XCTAssertFalse(components.url?.absoluteString.contains("synthetic-secret") == true)
    }

    private func makeFixtureAPI(named name: String) throws -> JellyfinAPI {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        let fixtureData = try Data(contentsOf: fixtureURL)
        GenreURLProtocol.handler = { request in Self.response(request, data: fixtureData) }
        return try makeAPI()
    }

    private func makeAPI() throws -> JellyfinAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenreURLProtocol.self]
        return JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid/reverse-proxy")),
            deviceID: "synthetic-device",
            token: "synthetic-secret",
            urlSession: URLSession(configuration: configuration)
        )
    }

    private static func query(_ request: URLRequest) throws -> [String: String] {
        let components = try XCTUnwrap(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        json: String
    ) -> (HTTPURLResponse, Data) {
        response(request, status: status, data: Data(json.utf8))
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        data: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

private final class GenreURLProtocol: URLProtocol, @unchecked Sendable {
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
