import Foundation
import XCTest
@testable import Jellytone

final class ArtistGatewayTests: XCTestCase {
    override func tearDown() {
        ArtistURLProtocol.handler = nil
        super.tearDown()
    }

    func testTopTracksRequestIsScopedPlayCountSortedAndBounded() async throws {
        var requests: [URLRequest] = []
        ArtistURLProtocol.handler = { request in
            requests.append(request)
            return Self.response(request, json: #"{"Items":[]}"#)
        }
        let api = try makeAPI()

        _ = try await api.artistTopTracks(
            userID: "account/id",
            artistID: "artist/id",
            libraryID: "library/id",
            limit: 999
        )
        _ = try await api.artistTopTracks(userID: "account/id", artistID: "artist/id", libraryID: nil, limit: 0)

        XCTAssertEqual(requests.count, 2)
        let scoped = try query(requests[0])
        XCTAssertEqual(scoped["userId"], "account/id")
        XCTAssertEqual(scoped["ArtistIds"], "artist/id")
        XCTAssertEqual(scoped["ParentId"], "library/id")
        XCTAssertEqual(scoped["IncludeItemTypes"], "Audio")
        XCTAssertEqual(scoped["Recursive"], "true")
        XCTAssertEqual(scoped["SortBy"], "PlayCount,SortName")
        XCTAssertEqual(scoped["SortOrder"], "Descending")
        XCTAssertEqual(scoped["Limit"], "25")
        XCTAssertEqual(scoped["StartIndex"], "0")
        XCTAssertEqual(scoped["EnableTotalRecordCount"], "false")

        let unscoped = try query(requests[1])
        XCTAssertNil(unscoped["ParentId"])
        XCTAssertEqual(unscoped["Limit"], "1")
        for request in requests {
            let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            XCTAssertEqual(components.path, "/reverse-proxy/Items")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-secret")
            XCTAssertFalse(components.url?.absoluteString.contains("synthetic-secret") == true)
        }
    }

    func testTopTracksMappingKeepsServerOrderDropsNonAudioAndDuplicateRows() async throws {
        ArtistURLProtocol.handler = { request in
            Self.response(request, json: #"""
            {"Items":[
                {"Id":"track-most-played","Name":"Most Played","Type":"Audio","Artists":["Synthetic Artist"],
                 "Album":"Aurora Lines","AlbumId":"album-a","RunTimeTicks":1810000000},
                {"Id":"album-a","Name":"Aurora Lines","Type":"MusicAlbum"},
                {"Id":"track-most-played","Name":"Most Played (duplicate row)","Type":"Audio"},
                {"Id":"","Name":"Malformed"},
                {"Id":"track-unicode","Name":"夜の音","Type":"Audio","Artists":[],"AlbumArtist":"Fallback Artist"}
            ]}
            """#)
        }
        let api = try makeAPI()

        let tracks = try await api.artistTopTracks(userID: "account", artistID: "artist", libraryID: nil)

        XCTAssertEqual(tracks.map(\.id), ["track-most-played", "track-unicode"])
        XCTAssertEqual(tracks[0].name, "Most Played")
        XCTAssertEqual(tracks[0].album, "Aurora Lines")
        XCTAssertEqual(tracks[0].albumID, "album-a")
        XCTAssertEqual(tracks[1].artist, "Fallback Artist")
    }

    func testTopTracksAuthenticationAndMalformedPayloadRemainTyped() async throws {
        let api = try makeAPI()
        ArtistURLProtocol.handler = { request in Self.response(request, status: 401, json: #"{}"#) }
        await XCTAssertThrowsErrorAsync(try await api.artistTopTracks(userID: "user", artistID: "artist", libraryID: nil)) {
            XCTAssertEqual($0 as? APIError, .httpStatus(401))
        }
        ArtistURLProtocol.handler = { request in Self.response(request, json: #"{"Items":{"not":"an-array"}}"#) }
        await XCTAssertThrowsErrorAsync(try await api.artistTopTracks(userID: "user", artistID: "artist", libraryID: nil)) {
            XCTAssertEqual($0 as? APIError, .invalidPayload)
        }
    }

    private func makeAPI() throws -> JellyfinAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtistURLProtocol.self]
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
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                            headerFields: ["Content-Type": "application/json"])!,
            Data(json.utf8)
        )
    }
}

private final class ArtistURLProtocol: URLProtocol, @unchecked Sendable {
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
