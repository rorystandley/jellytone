import Foundation
import XCTest
@testable import Jellytone

@MainActor
final class RecentAudioCacheTests: XCTestCase {
    func testRemembersServesAndSurvivesRelaunch() async throws {
        let workspace = temporaryDirectory()
        let cacheDir = workspace.appendingPathComponent("recent", isDirectory: true)
        let source = try writeSource(bytes: 2048, name: "a.mp3", in: workspace)

        let cache = RecentAudioCache(directory: cacheDir)
        XCTAssertNil(cache.localURL(for: "track-a"), "Cold cache is a miss")

        await cache.remember(trackID: "track-a", request: URLRequest(url: source))
        let hit = try XCTUnwrap(cache.localURL(for: "track-a"))
        XCTAssertEqual(try Data(contentsOf: hit).count, 2048)

        // A second instance over the same directory rebuilds its index.
        let relaunched = RecentAudioCache(directory: cacheDir)
        XCTAssertNotNil(relaunched.localURL(for: "track-a"))

        cache.clear()
        XCTAssertNil(cache.localURL(for: "track-a"))
        XCTAssertEqual(cache.totalBytes, 0)
    }

    func testRemoveDropsACachedTrack() async throws {
        let workspace = temporaryDirectory()
        let cacheDir = workspace.appendingPathComponent("recent", isDirectory: true)
        let source = try writeSource(bytes: 512, name: "a.mp3", in: workspace)
        let cache = RecentAudioCache(directory: cacheDir)

        await cache.remember(trackID: "track-a", request: URLRequest(url: source))
        XCTAssertNotNil(cache.localURL(for: "track-a"))
        cache.remove(trackID: "track-a")
        XCTAssertNil(cache.localURL(for: "track-a"))
        XCTAssertEqual(cache.totalBytes, 0)
    }

    func testEnqueuePrefetchesUncachedTracks() async throws {
        let workspace = temporaryDirectory()
        let cacheDir = workspace.appendingPathComponent("recent", isDirectory: true)
        let source = try writeSource(bytes: 256, name: "a.mp3", in: workspace)
        let cache = RecentAudioCache(directory: cacheDir)

        cache.enqueue([(trackID: "track-a", request: URLRequest(url: source))])
        for _ in 0..<50 where cache.localURL(for: "track-a") == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(cache.localURL(for: "track-a"))
        XCTAssertEqual(cache.totalBytes, 256)
    }

    func testLRUEvictsLeastRecentlyUsedOverBudget() async throws {
        let workspace = temporaryDirectory()
        let cacheDir = workspace.appendingPathComponent("recent", isDirectory: true)
        // Budget holds two 1 KB files but not three.
        let cache = RecentAudioCache(directory: cacheDir, byteBudget: 2200)

        for id in ["one", "two"] {
            let src = try writeSource(bytes: 1024, name: "\(id).mp3", in: workspace)
            await cache.remember(trackID: id, request: URLRequest(url: src))
        }
        // Touch "one" so "two" becomes least-recently-used.
        XCTAssertNotNil(cache.localURL(for: "one"))

        let third = try writeSource(bytes: 1024, name: "three.mp3", in: workspace)
        await cache.remember(trackID: "three", request: URLRequest(url: third))

        XCTAssertNotNil(cache.localURL(for: "one"), "Recently used survives")
        XCTAssertNotNil(cache.localURL(for: "three"), "Newest survives")
        XCTAssertNil(cache.localURL(for: "two"), "Least-recently-used is evicted")
    }

    func testRepeatedRememberIsIdempotent() async throws {
        let workspace = temporaryDirectory()
        let cacheDir = workspace.appendingPathComponent("recent", isDirectory: true)
        let source = try writeSource(bytes: 512, name: "a.mp3", in: workspace)
        let cache = RecentAudioCache(directory: cacheDir)

        await cache.remember(trackID: "track-a", request: URLRequest(url: source))
        await cache.remember(trackID: "track-a", request: URLRequest(url: source))
        XCTAssertEqual(cache.totalBytes, 512, "The same track is stored once")
    }

    // MARK: Helpers

    private func writeSource(bytes: Int, name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data((0..<bytes).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    private func temporaryDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentAudioCacheTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}
