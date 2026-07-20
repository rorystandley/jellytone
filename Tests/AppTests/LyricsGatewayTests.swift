import Foundation
import XCTest
@testable import Jellytone

final class LyricsGatewayTests: XCTestCase {
    override func tearDown() {
        LyricsURLProtocol.handler = nil
        super.tearDown()
    }

    func testSyncedLyricsMapTicksToSecondsAndDriveActiveLine() async throws {
        LyricsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/reverse-proxy/Audio/track-a/Lyrics")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "synthetic-secret")
            return Self.response(request, json: #"""
            {"Lyrics":[
              {"Text":"First line","Start":0},
              {"Text":"Second line","Start":40000000},
              {"Text":"Third line","Start":80000000}
            ]}
            """#)
        }
        let api = try makeAPI()

        let lyrics = try await XCTUnwrapAsync(await api.lyrics(itemID: "track-a"))
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), ["First line", "Second line", "Third line"])
        XCTAssertEqual(lyrics.lines[1].startSeconds, 4)          // 40,000,000 ticks
        XCTAssertEqual(lyrics.activeIndex(at: 0), 0)
        XCTAssertEqual(lyrics.activeIndex(at: 5), 1)
        XCTAssertEqual(lyrics.activeIndex(at: 100), 2)
    }

    func testUnsyncedLyricsHaveNoTimingAndNoActiveLine() async throws {
        LyricsURLProtocol.handler = { request in
            Self.response(request, json: #"{"Lyrics":[{"Text":"Just words"},{"Text":"No timing"}]}"#)
        }
        let api = try makeAPI()

        let lyrics = try await XCTUnwrapAsync(await api.lyrics(itemID: "track-a"))
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertNil(lyrics.lines.first?.startSeconds)
        XCTAssertNil(lyrics.activeIndex(at: 30))
    }

    func testMissingLyricsReturnNilRatherThanThrowing() async throws {
        LyricsURLProtocol.handler = { request in
            Self.response(request, status: 404, json: #"{"error":"not found"}"#)
        }
        let api = try makeAPI()

        let lyrics = try await api.lyrics(itemID: "track-a")
        XCTAssertNil(lyrics)
    }

    // MARK: Harness

    private func makeAPI() throws -> JellyfinAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        return JellyfinAPI(
            baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid/reverse-proxy")),
            deviceID: "synthetic-device",
            token: "synthetic-secret",
            urlSession: URLSession(configuration: configuration)
        )
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }

    private static func response(_ request: URLRequest, status: Int = 200, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }
}

private final class LyricsURLProtocol: URLProtocol, @unchecked Sendable {
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
