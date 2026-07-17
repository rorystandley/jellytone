import Foundation
import MediaPlayer
import UIKit
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

    func testPlaybackInfoSelectsSupportedDirectSource() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/jellyfin/Items/track/PlaybackInfo")
            return Self.response(
                for: request,
                json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"session"}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com/jellyfin")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let plan = try await api.playbackPlan(itemID: "track", userID: "user")
        XCTAssertEqual(plan.method, .directPlay)
        XCTAssertEqual(plan.url.path, "/jellyfin/Audio/track/stream")
        let query = try XCTUnwrap(URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "mediaSourceId" })?.value, "source")
        XCTAssertEqual(query.first(where: { $0.name == "playSessionId" })?.value, "session")
    }

    func testPlaybackInfoFallsBackToProvenAACTranscode() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                json: #"{"MediaSources":[{"Id":"source","Container":"wma","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"wmav2"}]}],"PlaySessionId":"session"}"#
            )
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let plan = try await api.playbackPlan(itemID: "track", userID: "user")
        XCTAssertEqual(plan.method, .transcode)
        XCTAssertEqual(plan.url.path, "/Audio/track/universal")
        let query = try XCTUnwrap(URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "audioCodec" })?.value, "aac")
        XCTAssertEqual(query.first(where: { $0.name == "enableDirectPlay" })?.value, "false")
    }

    func testPlaybackStartReportUsesJellyfinTicks() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/Sessions/Playing")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["PlayMethod"] as? String, "DirectPlay")
            XCTAssertEqual(json["PositionTicks"] as? Int64, 125_000_000)
            XCTAssertEqual(json["IsPaused"] as? Bool, false)
            return Self.response(for: request, status: 204, json: "")
        }
        let api = JellyfinAPI(baseURL: try XCTUnwrap(URL(string: "https://example.com")),
                              deviceID: "device", token: "token", urlSession: makeSession())
        let plan = PlaybackPlan(url: try XCTUnwrap(URL(string: "https://example.com/audio")),
                                mediaSourceID: "source", playSessionID: "session", method: .directPlay)
        await api.reportStarted(itemID: "track", plan: plan, position: 12.5, paused: false)
    }

    func testPlaybackSnapshotRoundTripsQueueAndPosition() throws {
        let track = Track(id: "track", name: "Track", artist: "Artist", album: "Album",
                          albumID: "album", index: 1, disc: 1, durationTicks: 600_000_000)
        let snapshot = PlaybackSnapshot(scope: "server:user", queue: [track], currentIndex: 0, position: 42.5)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    @MainActor
    func testNowPlayingArtworkCanBeRequestedOffMainActor() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let artwork = UncheckedSendable(value: NowPlayingArtworkFactory.make(from: image))

        let generatedImage = await Task.detached {
            artwork.value.image(at: CGSize(width: 1, height: 1)) != nil
        }.value

        XCTAssertTrue(generatedImage)
    }

    @MainActor
    func testPlaybackActivatesBackgroundAudioSessionBeforePreparingStream() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/Items/track/PlaybackInfo")
            return Self.response(
                for: request,
                json: #"{"MediaSources":[{"Id":"source","Container":"mp3","SupportsDirectPlay":true,"SupportsTranscoding":true,"MediaStreams":[{"Type":"Audio","Codec":"mp3"}]}],"PlaySessionId":"session"}"#
            )
        }
        let session = RecordingAudioSession()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let playback = PlaybackController(defaults: defaults, audioSession: session)
        let api = JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://example.com")),
            deviceID: "device",
            token: "token",
            urlSession: makeSession()
        )
        let track = Track(
            id: "track",
            name: "Track",
            artist: "Artist",
            album: "Album",
            index: 1,
            disc: 1,
            durationTicks: 600_000_000
        )

        playback.play(track, queue: [track], using: api, userID: "user", scope: "server:user")
        for _ in 0..<20 where session.activationCount == 0 { await Task.yield() }

        XCTAssertEqual(session.activationCount, 1)
        playback.stop()
        XCTAssertEqual(session.deactivationCount, 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
        response(for: request, status: 200, json: json)
    }

    private static func response(for request: URLRequest, status: Int, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
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

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor
private final class RecordingAudioSession: AudioSessionManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    func activateForPlayback() throws { activationCount += 1 }
    func deactivateAfterPlayback() throws { deactivationCount += 1 }
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
