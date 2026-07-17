import Foundation
import XCTest
@testable import JellyfinAudio

final class FavouritesGatewayTests: XCTestCase {
    override func tearDown() {
        FavouritesURLProtocol.handler = nil
        super.tearDown()
    }

    func testFavouriteFixtureFiltersContradictionsAndPreservesStableOccurrences() async throws {
        let api = try fixtureAPI()

        let artists = try await api.favouriteArtists(userID: "account", libraryID: "library", limit: 20)
        let albums = try await api.favouriteAlbums(userID: "account", libraryID: "library", limit: 20)
        let tracks = try await api.favouriteTracks(userID: "account", libraryID: "library", startIndex: 20, limit: 20)

        XCTAssertEqual(artists.artists.map(\.id), ["artist-a", "artist-a"])
        XCTAssertEqual(artists.artists.first?.imageTag, "artist-art-a")
        XCTAssertEqual(albums.albums.map(\.id), ["album-a", "album-a"])
        XCTAssertEqual(albums.albums.first?.artist, "Various Artists")
        XCTAssertEqual(tracks.occurrences.map(\.track.id), ["track-a", "track-a"])
        XCTAssertEqual(tracks.occurrences.map(\.id), ["favourite:25:track-a", "favourite:26:track-a"])
        XCTAssertNotEqual(tracks.occurrences[0].id, tracks.occurrences[1].id)
        XCTAssertEqual(tracks.nextStartIndex, 31, "Raw wire rows, including malformed rows, advance the cursor")
        XCTAssertFalse(tracks.hasMore)
    }

    func testFavouriteRequestsAreAccountLibraryScopedAndUseExactTypes() async throws {
        var requests: [URLRequest] = []
        FavouritesURLProtocol.handler = { request in
            requests.append(request)
            return Self.response(request, json: #"{"Items":[],"TotalRecordCount":0}"#)
        }
        let api = try makeAPI()
        _ = try await api.favouriteArtists(userID: "account/id", libraryID: "library/id", startIndex: 1, limit: 2)
        _ = try await api.favouriteAlbums(userID: "account/id", libraryID: "library/id", startIndex: 3, limit: 4)
        _ = try await api.favouriteTracks(userID: "account/id", libraryID: "library/id", startIndex: 5, limit: 6)

        XCTAssertEqual(requests.count, 3)
        for (request, expectedType) in zip(requests, ["MusicArtist", "MusicAlbum", "Audio"]) {
            let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
            XCTAssertEqual(components.path, "/reverse-proxy/Items")
            XCTAssertEqual(query["userId"], "account/id")
            XCTAssertEqual(query["ParentId"], "library/id")
            XCTAssertEqual(query["IncludeItemTypes"], expectedType)
            XCTAssertEqual(query["IsFavorite"], "true")
            XCTAssertEqual(query["Recursive"], "true")
            XCTAssertEqual(query["EnableTotalRecordCount"], "true")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-secret")
            XCTAssertFalse(components.url?.absoluteString.contains("synthetic-secret") == true)
        }
    }

    func testFavouriteErrorsAndCancellationRemainTyped() async throws {
        let api = try makeAPI()
        FavouritesURLProtocol.handler = { request in Self.response(request, status: 401, json: #"{}"#) }
        do {
            _ = try await api.favouriteArtists(userID: "user", libraryID: "library")
            XCTFail("Expected authentication expiry")
        } catch {
            XCTAssertEqual(error as? APIError, .httpStatus(401))
        }
        FavouritesURLProtocol.handler = { _ in throw URLError(.cancelled) }
        do {
            _ = try await api.favouriteTracks(userID: "user", libraryID: "library")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func fixtureAPI() throws -> JellyfinAPI {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "favourites", withExtension: "json"))
        let data = try Data(contentsOf: url)
        FavouritesURLProtocol.handler = { request in Self.response(request, data: data) }
        return try makeAPI()
    }

    private func makeAPI() throws -> JellyfinAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavouritesURLProtocol.self]
        return JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid/reverse-proxy")), deviceID: "device", token: "synthetic-secret", urlSession: URLSession(configuration: configuration))
    }

    private static func response(_ request: URLRequest, status: Int = 200, json: String) -> (HTTPURLResponse, Data) { response(request, status: status, data: Data(json.utf8)) }
    private static func response(_ request: URLRequest, status: Int = 200, data: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
    }
}

private final class FavouritesURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (response, data) = try XCTUnwrap(Self.handler)(request); client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self) }
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
