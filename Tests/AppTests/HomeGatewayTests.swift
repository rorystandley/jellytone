import Foundation
import XCTest
@testable import Jellytone

final class HomeGatewayTests: XCTestCase {
    override func tearDown() {
        HomeURLProtocol.handler = nil
        super.tearDown()
    }

    func testRecentlyAddedFixturePreservesServerOrderAndRejectsMalformedOrNonAlbumRows() async throws {
        let api = try makeFixtureAPI(named: "home-recently-added")

        let albums = try await api.recentlyAddedAlbums(
            userID: "synthetic-account",
            libraryID: "synthetic-library",
            limit: 20
        )

        XCTAssertEqual(albums.map(\.id), [
            "album-newest", "album-tie-b", "album-tie-a", "album-unicode", "album-minimal",
        ])
        XCTAssertEqual(albums.filter { $0.name == "Same Date" }.map(\.id), ["album-tie-b", "album-tie-a"])
        XCTAssertEqual(albums.first { $0.id == "album-unicode" }?.name, "Café 東京 🎧")
        XCTAssertNil(albums.first { $0.id == "album-minimal" }?.imageTag)
        XCTAssertEqual(albums.first { $0.id == "album-minimal" }?.artist, "Unknown Artist")
    }

    func testRecentlyPlayedFixturePreservesHistoryOrderStableIdentityAndPlayableTracks() async throws {
        let api = try makeFixtureAPI(named: "home-recently-played")

        let tracks = try await api.recentlyPlayedTracks(
            userID: "synthetic-account",
            libraryID: "synthetic-library",
            limit: 20
        )

        XCTAssertEqual(tracks.map(\.id), ["track-recent", "track-tie-b", "track-tie-a", "track-unicode", "track-minimal"])
        XCTAssertEqual(tracks.filter { $0.name == "Same Play Time" }.map(\.id), ["track-tie-b", "track-tie-a"])
        XCTAssertEqual(tracks.first { $0.id == "track-unicode" }?.name, "Cafe\u{301} Finale 東京")
        XCTAssertEqual(tracks.first { $0.id == "track-unicode" }?.artist, "Unicode Artist")
        XCTAssertNil(tracks.first { $0.id == "track-minimal" }?.durationTicks)
    }

    func testHomeShelfRequestsAreScopedMusicOnlyBoundedAndUseSupportedHistorySorts() async throws {
        var requests: [URLRequest] = []
        HomeURLProtocol.handler = { request in
            requests.append(request)
            return Self.response(request, json: #"{"Items":[]}"#)
        }
        let api = try makeAPI()

        _ = try await api.recentlyAddedAlbums(userID: "account/id", libraryID: "library/id", limit: 999)
        _ = try await api.recentlyPlayedTracks(userID: "account/id", libraryID: "library/id", limit: 0)
        _ = try await api.frequentlyPlayedAlbums(userID: "account/id", libraryID: "library/id", limit: 16)
        _ = try await api.rediscoverAlbums(userID: "account/id", libraryID: "library/id", limit: 16)
        _ = try await api.instantMixTracks(userID: "account/id", itemID: "seed-artist", limit: 50)

        XCTAssertEqual(requests.count, 5)
        let added = try query(requests[0])
        XCTAssertEqual(added["userId"], "account/id")
        XCTAssertEqual(added["ParentId"], "library/id")
        XCTAssertEqual(added["IncludeItemTypes"], "MusicAlbum")
        XCTAssertEqual(added["SortBy"], "DateCreated,SortName")
        XCTAssertEqual(added["SortOrder"], "Descending")
        XCTAssertEqual(added["Limit"], "100")
        XCTAssertEqual(added["StartIndex"], "0")
        XCTAssertEqual(added["EnableTotalRecordCount"], "false")

        let played = try query(requests[1])
        XCTAssertEqual(played["userId"], "account/id")
        XCTAssertEqual(played["ParentId"], "library/id")
        XCTAssertEqual(played["IncludeItemTypes"], "Audio")
        XCTAssertEqual(played["IsPlayed"], "true")
        XCTAssertEqual(played["SortBy"], "DatePlayed")
        XCTAssertEqual(played["SortOrder"], "Descending")
        XCTAssertEqual(played["Limit"], "1")

        let top = try query(requests[2])
        XCTAssertEqual(top["userId"], "account/id")
        XCTAssertEqual(top["ParentId"], "library/id")
        XCTAssertEqual(top["IncludeItemTypes"], "MusicAlbum")
        XCTAssertEqual(top["SortBy"], "PlayCount,SortName")
        XCTAssertEqual(top["SortOrder"], "Descending")
        XCTAssertEqual(top["Limit"], "16")

        let rediscover = try query(requests[3])
        XCTAssertEqual(rediscover["SortBy"], "Random")
        XCTAssertEqual(rediscover["IncludeItemTypes"], "MusicAlbum")
        XCTAssertEqual(rediscover["ParentId"], "library/id")

        let mixRequest = requests[4]
        let mixComponents = try XCTUnwrap(mixRequest.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(mixComponents.path, "/reverse-proxy/Items/seed-artist/InstantMix")
        let mix = try query(mixRequest)
        XCTAssertEqual(mix["userId"], "account/id")
        XCTAssertEqual(mix["Limit"], "50")

        for request in requests {
            let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            XCTAssertTrue(components.path.hasPrefix("/reverse-proxy/Items"), components.path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-secret")
            XCTAssertFalse(components.url?.absoluteString.contains("synthetic-secret") == true)
        }
    }

    func testHomeShelfAuthenticationMalformedPayloadAndCancellationRemainTyped() async throws {
        let api = try makeAPI()
        HomeURLProtocol.handler = { request in Self.response(request, status: 401, json: #"{}"#) }
        await XCTAssertThrowsErrorAsync(try await api.recentlyAddedAlbums(userID: "user", libraryID: "library")) {
            XCTAssertEqual($0 as? APIError, .httpStatus(401))
        }
        HomeURLProtocol.handler = { request in Self.response(request, json: #"{"Items":{"not":"an-array"}}"#) }
        await XCTAssertThrowsErrorAsync(try await api.recentlyPlayedTracks(userID: "user", libraryID: "library")) {
            XCTAssertEqual($0 as? APIError, .invalidPayload)
        }
        HomeURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await XCTAssertThrowsErrorAsync(try await api.recentlyPlayedTracks(userID: "user", libraryID: "library")) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    private func makeFixtureAPI(named name: String) throws -> JellyfinAPI {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        let fixtureData = try Data(contentsOf: fixtureURL)
        HomeURLProtocol.handler = { request in Self.response(request, data: fixtureData) }
        return try makeAPI()
    }

    private func makeAPI() throws -> JellyfinAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeURLProtocol.self]
        return JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid/reverse-proxy")),
            deviceID: "synthetic-device",
            token: "synthetic-secret",
            urlSession: URLSession(configuration: configuration)
        )
    }

    private func query(_ request: URLRequest) throws -> [String: String] {
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    private static func response(_ request: URLRequest, status: Int = 200, json: String) -> (HTTPURLResponse, Data) {
        response(request, status: status, data: Data(json.utf8))
    }

    private static func response(_ request: URLRequest, status: Int = 200, data: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
    }
}

private final class HomeURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch { handler(error) }
}
