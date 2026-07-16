import Foundation
import XCTest
@testable import JellyfinAudio

final class MinimumWorkingAppTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testTrackDurationUsesJellyfinTicks() {
        let track = Track(id: "track", name: "Synthetic", artist: "Artist", album: "Album",
                          index: 1, disc: 1, durationTicks: 1_250_000_000)
        XCTAssertEqual(track.duration, 125)
        XCTAssertEqual(track.durationLabel, "2:05")
    }

    func testArtworkRequestPreservesReverseProxyBasePathAndUsesHeaderToken() throws {
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
            deviceID: "synthetic-device",
            token: "synthetic-token"
        )
        let request = try api.artworkRequest(itemID: "album")
        XCTAssertEqual(request.url?.path, "/jellyfin/Items/album/Images/Primary")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-token")
        XCTAssertFalse(request.url?.absoluteString.contains("synthetic-token") == true)
    }

    func testStreamURLPreservesBasePathAndCarriesTokenOnlyForAVPlayer() throws {
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com/base")),
            deviceID: "synthetic-device",
            token: "synthetic-token"
        )
        let components = try XCTUnwrap(URLComponents(url: api.streamURL(itemID: "track"), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/base/Audio/track/stream")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api_key" })?.value, "synthetic-token")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "static" })?.value, "true")
    }

    func testAuthenticationMapsTokenAndUserWithoutLoggingCredentials() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/jellyfin/Users/AuthenticateByName")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.contains("synthetic-device") == true)
            let body = try Self.bodyData(from: request)
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: body) as? NSDictionary,
                ["Username": "listener", "Pw": "temporary-password"]
            )
            return Self.response(
                for: request,
                json: #"{"AccessToken":"synthetic-token","User":{"Id":"user-id","Name":"Listener"}}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
                              deviceID: "synthetic-device", urlSession: makeSession())
        let result = try await api.authenticate(username: "listener", password: "temporary-password")
        XCTAssertEqual(result.token, "synthetic-token")
        XCTAssertEqual(result.userID, "user-id")
        XCTAssertEqual(result.username, "Listener")
    }

    func testMusicViewsFilterOutNonMusicLibraries() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                json: #"{"Items":[{"Id":"music","Name":"Music","CollectionType":"music"},{"Id":"movies","Name":"Movies","CollectionType":"movies"}]}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "synthetic-device", token: "token", urlSession: makeSession())
        let libraries = try await api.musicLibraries(userID: "user")
        XCTAssertEqual(libraries, [MusicLibrary(id: "music", name: "Music")])
    }

    func testGlobalAlbumFallbackUsesCurrentItemsEndpoint() async throws {
        MockURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/jellyfin/Items")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "userId" })?.value, "user")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "IncludeItemTypes" })?.value, "MusicAlbum")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "Limit" })?.value, "100")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "EnableTotalRecordCount" })?.value, "false")
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "ParentId" }))
            return Self.response(
                for: request,
                json: #"{"Items":[{"Id":"album","Name":"Synthetic Album","AlbumArtist":"Synthetic Artist"}]}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
                              deviceID: "synthetic-device", token: "token", urlSession: makeSession())
        let page = try await api.albums(userID: "user", libraryID: nil)
        XCTAssertEqual(page.albums.first?.name, "Synthetic Album")
        XCTAssertEqual(page.albums.first?.artist, "Synthetic Artist")
        XCTAssertFalse(page.hasMore)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (response, Data(json.utf8))
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { break }
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
