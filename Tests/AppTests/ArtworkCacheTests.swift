import UIKit
import XCTest
@testable import Jellytone

final class ArtworkCacheTests: XCTestCase {
    func testStoreLoadSizeAndClearRoundTrip() async throws {
        let directory = temporaryDirectory()
        let cache = ArtworkCache(directory: directory)
        let key = ArtworkCache.key(serverID: "server-a", itemID: "item-1")
        let data = Self.tinyPNGData()

        let miss = await cache.image(forKey: key)
        XCTAssertNil(miss)

        await cache.store(data, forKey: key)
        let hit = await cache.image(forKey: key)
        XCTAssertNotNil(hit)

        // A fresh instance over the same directory reads from disk.
        let relaunched = ArtworkCache(directory: directory)
        let diskHit = await relaunched.image(forKey: key)
        XCTAssertNotNil(diskHit)

        let bytes = await cache.diskBytes()
        XCTAssertGreaterThan(bytes, 0)

        XCTAssertNotNil(ArtworkCache.memoryImage(forKey: key))

        await cache.clear()
        let cleared = await cache.image(forKey: key)
        XCTAssertNil(cleared)
        let emptyBytes = await cache.diskBytes()
        XCTAssertEqual(emptyBytes, 0)
    }

    func testStoreOverwritesAndRevalidationIsOncePerInstance() async throws {
        let directory = temporaryDirectory()
        let cache = ArtworkCache(directory: directory)
        let key = ArtworkCache.key(serverID: "server-a", itemID: "item-1")

        await cache.store(Self.tinyPNGData(color: .systemRed), forKey: key)
        let firstRevalidation = await cache.takeRevalidation(forKey: key)
        XCTAssertTrue(firstRevalidation)
        let secondRevalidation = await cache.takeRevalidation(forKey: key)
        XCTAssertFalse(secondRevalidation, "Only the first reader fetches")

        await cache.store(Self.tinyPNGData(color: .systemBlue), forKey: key)
        let overwritten = await cache.image(forKey: key)
        XCTAssertNotNil(overwritten)

        await cache.allowRevalidation(forKey: key)
        let afterAllow = await cache.takeRevalidation(forKey: key)
        XCTAssertTrue(afterAllow)

        await cache.clear()
        let afterClear = await cache.takeRevalidation(forKey: key)
        XCTAssertTrue(afterClear, "Clear resets the session revalidation set")
    }

    func testNonImagePayloadAndHostileKeysAreContained() async throws {
        let directory = temporaryDirectory()
        let cache = ArtworkCache(directory: directory)

        // Junk bytes are never stored as an image.
        await cache.store(Data([0x00, 0x01, 0x02]), forKey: "junk")
        let junk = await cache.image(forKey: "junk")
        XCTAssertNil(junk)

        // A path-traversal key hashes to a flat filename inside the directory.
        let hostileKey = "../../escape"
        await cache.store(Self.tinyPNGData(), forKey: hostileKey)
        let contained = await cache.image(forKey: hostileKey)
        XCTAssertNotNil(contained)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].contains(".."))
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkCacheTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private static func tinyPNGData(color: UIColor = .systemRed) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData() ?? Data()
    }
}
