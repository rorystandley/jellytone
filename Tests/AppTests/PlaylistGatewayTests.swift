import Foundation
import XCTest
@testable import JellyfinAudio

final class PlaylistGatewayTests: XCTestCase {
    override func tearDown() {
        PlaylistURLProtocol.handler = nil
        super.tearDown()
    }

    func testPlaylistFixturePreservesIdentityDuplicateNamesUnicodeArtAndCounts() async throws {
        let api = try makeFixtureAPI(named: "playlists")

        let page = try await api.playlists(
            userID: "synthetic-user",
            libraryID: "synthetic-library",
            startIndex: 0,
            limit: 20
        )

        XCTAssertEqual(page.playlists.map(\.id), [
            "playlist-road-a", "playlist-road-b", "playlist-unicode", "playlist-no-count",
        ])
        XCTAssertEqual(page.playlists.filter { $0.name == "Road Mix" }.map(\.id), [
            "playlist-road-a", "playlist-road-b",
        ])
        XCTAssertEqual(page.playlists.first { $0.id == "playlist-unicode" }?.name, "Café 東京 🎧")
        XCTAssertEqual(page.playlists.first { $0.id == "playlist-road-a" }?.imageTag, "playlist-art-a")
        XCTAssertEqual(page.playlists.first { $0.id == "playlist-road-a" }?.itemCount, 4)
        XCTAssertEqual(page.playlists.first { $0.id == "playlist-road-b" }?.itemCount, 0)
        XCTAssertNil(page.playlists.first { $0.id == "playlist-no-count" }?.imageTag)
        XCTAssertNil(page.playlists.first { $0.id == "playlist-no-count" }?.itemCount)
        XCTAssertEqual(page.nextStartIndex, 8, "Every wire record must advance the cursor")
        XCTAssertFalse(page.hasMore)
    }

    func testPlaylistRequestPreservesBasePathAuthenticationAndUsesGlobalPlaylistScope() async throws {
        PlaylistURLProtocol.handler = { request in
            let components = try XCTUnwrap(request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            })
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(components.path, "/reverse-proxy/Items")
            XCTAssertEqual(query["userId"], "user id")
            XCTAssertFalse(
                query.keys.contains("ParentId"),
                "Jellyfin playlists are global rather than music-view children"
            )
            XCTAssertEqual(query["IncludeItemTypes"], "Playlist")
            XCTAssertEqual(query["Recursive"], "true")
            XCTAssertEqual(query["StartIndex"], "25")
            XCTAssertEqual(query["Limit"], "10")
            XCTAssertEqual(query["EnableTotalRecordCount"], "true")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-secret")
            XCTAssertFalse(components.url?.absoluteString.contains("synthetic-secret") == true)
            return Self.response(request, json: #"{"Items":[],"TotalRecordCount":25}"#)
        }
        let api = try makeAPI()

        _ = try await api.playlists(
            userID: "user id",
            libraryID: "library/id",
            startIndex: 25,
            limit: 10
        )
    }

    func testPlaylistEntryFixturePreservesServerOrderDuplicateOccurrencesAndMalformedWireOffsets() async throws {
        let api = try makeFixtureAPI(named: "playlist-entries")

        let page = try await api.playlistEntries(
            userID: "synthetic-user",
            playlistID: "playlist-fixture",
            startIndex: 0,
            limit: 20
        )

        XCTAssertEqual(page.entries.map(\.id), [
            "occurrence-a-1", "occurrence-duplicate-1", "occurrence-duplicate-2",
            "occurrence-unicode", "playlist-fixture:7:track-fallback",
        ])
        XCTAssertEqual(page.entries.map(\.track.id), [
            "track-a", "track-duplicate", "track-duplicate", "track-unicode", "track-fallback",
        ])
        XCTAssertNotEqual(page.entries[1].id, page.entries[1].track.id)
        XCTAssertNotEqual(page.entries[1].id, page.entries[2].id)
        XCTAssertEqual(page.entries[3].track.name, "Cafe\u{301} Finale 東京")
        XCTAssertEqual(page.entries[3].track.artist, "Unicode Artist")
        XCTAssertNil(page.entries[3].track.durationTicks)
        XCTAssertEqual(page.entries[4].track.artist, "Unknown Artist")
        XCTAssertEqual(page.entries[4].track.album, "")
        XCTAssertEqual(page.nextStartIndex, 8)
        XCTAssertFalse(page.hasMore)
    }

    func testPlaylistEntryRequestDoesNotAskServerToResortEntries() async throws {
        PlaylistURLProtocol.handler = { request in
            let components = try XCTUnwrap(request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            })
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(components.path, "/reverse-proxy/Playlists/playlist id/Items")
            XCTAssertEqual(query["userId"], "user")
            XCTAssertEqual(query["StartIndex"], "40")
            XCTAssertEqual(query["Limit"], "20")
            XCTAssertFalse(query.keys.contains("SortBy"))
            XCTAssertFalse(query.keys.contains("SortOrder"))
            return Self.response(request, json: #"{"Items":[],"TotalRecordCount":40}"#)
        }
        let api = try makeAPI()

        _ = try await api.playlistEntries(
            userID: "user",
            playlistID: "playlist id",
            startIndex: 40,
            limit: 20
        )
    }

    func testPaginationAppendsPagesAndAdvancesByWireCountInsteadOfMappedCount() async throws {
        PlaylistURLProtocol.handler = { request in
            let components = try XCTUnwrap(request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            })
            let start = components.queryItems?.first { $0.name == "StartIndex" }?.value
            if start == "0" {
                return Self.response(
                    request,
                    json: #"{"Items":[{"Id":"playlist-a","Name":"First","Type":"Playlist"},17],"TotalRecordCount":3}"#
                )
            }
            XCTAssertEqual(start, "2")
            return Self.response(
                request,
                json: #"{"Items":[{"Id":"playlist-b","Name":"Second","Type":"Playlist"}],"TotalRecordCount":3}"#
            )
        }
        let api = try makeAPI()

        let first = try await api.playlists(userID: "user", libraryID: nil, startIndex: 0, limit: 2)
        XCTAssertEqual(first.playlists.map(\.id), ["playlist-a"])
        XCTAssertEqual(first.nextStartIndex, 2)
        XCTAssertTrue(first.hasMore)
        let second = try await api.playlists(
            userID: "user",
            libraryID: nil,
            startIndex: first.nextStartIndex,
            limit: 2
        )

        XCTAssertEqual((first.playlists + second.playlists).map(\.id), ["playlist-a", "playlist-b"])
        XCTAssertEqual(second.nextStartIndex, 3)
        XCTAssertFalse(second.hasMore)
    }

    func testPartialPageWithoutTotalRecordCountTerminatesWhileFullPageContinues() async throws {
        PlaylistURLProtocol.handler = { request in
            let limit = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "Limit" }?.value
            let items = limit == "2"
                ? #"[{"Id":"a","Name":"A","Type":"Playlist"},{"Id":"b","Name":"B","Type":"Playlist"}]"#
                : #"[{"Id":"a","Name":"A","Type":"Playlist"}]"#
            return Self.response(request, json: "{\"Items\":\(items)}")
        }
        let api = try makeAPI()

        let full = try await api.playlists(userID: "user", libraryID: nil, limit: 2)
        let partial = try await api.playlists(userID: "user", libraryID: nil, limit: 3)

        XCTAssertTrue(full.hasMore)
        XCTAssertFalse(partial.hasMore)
    }

    func testMalformedPayloadAndAuthenticationExpiryRemainTypedErrors() async throws {
        let api = try makeAPI()
        PlaylistURLProtocol.handler = { request in
            Self.response(request, json: #"{"Items":{"not":"an-array"}}"#)
        }
        do {
            _ = try await api.playlists(userID: "user", libraryID: nil)
            XCTFail("Expected malformed payload to fail")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidPayload)
        }

        PlaylistURLProtocol.handler = { request in
            Self.response(request, status: 401, json: #"{"error":"expired"}"#)
        }
        do {
            _ = try await api.playlistEntries(userID: "user", playlistID: "playlist")
            XCTFail("Expected authentication expiry to fail")
        } catch {
            XCTAssertEqual(error as? APIError, .httpStatus(401))
        }
    }

    func testCancelledPlaylistRequestSurfacesCancellationError() async throws {
        PlaylistURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let api = try makeAPI()

        do {
            _ = try await api.playlists(userID: "user", libraryID: nil)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func makeFixtureAPI(named name: String) throws -> JellyfinAPI {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        let fixtureData = try Data(contentsOf: fixtureURL)
        PlaylistURLProtocol.handler = { request in Self.response(request, data: fixtureData) }
        return try makeAPI()
    }

    private func makeAPI() throws -> JellyfinAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaylistURLProtocol.self]
        return JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid/reverse-proxy")),
            deviceID: "synthetic-device",
            token: "synthetic-secret",
            urlSession: URLSession(configuration: configuration)
        )
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

private final class PlaylistURLProtocol: URLProtocol, @unchecked Sendable {
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
