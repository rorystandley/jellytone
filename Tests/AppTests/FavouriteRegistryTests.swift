import XCTest
@testable import Jellytone

final class FavouriteRegistryTests: XCTestCase {
    func testToggleFlipsEffectiveStateForAnyItemKind() {
        var registry = FavouriteRegistry()
        XCTAssertFalse(registry.isFavourite("song-1"))

        XCTAssertTrue(registry.toggle("song-1"))
        XCTAssertTrue(registry.toggle("album-1"))
        XCTAssertTrue(registry.toggle("artist-1"))
        XCTAssertEqual(registry.favourites, ["song-1", "album-1", "artist-1"])

        XCTAssertFalse(registry.toggle("album-1"))
        XCTAssertEqual(registry.favourites, ["song-1", "artist-1"])
    }

    func testPendingIntentWinsOverContradictingServerTruth() {
        var registry = FavouriteRegistry()
        // User likes an album that the server load then reports as not-favourited
        // (the write hasn't reconciled yet). The optimistic like must survive.
        registry.setDesired("album-1", true)
        registry.applyServerTruth(favourited: [], observed: ["album-1"])
        XCTAssertTrue(registry.isFavourite("album-1"))

        // And an optimistic un-like survives a stale favourited server truth.
        registry.setDesired("song-2", false)
        registry.applyServerTruth(favourited: ["song-2"], observed: ["song-2"])
        XCTAssertFalse(registry.isFavourite("song-2"))
    }

    func testServerTruthDrivesItemsWithoutPendingIntent() {
        var registry = FavouriteRegistry()
        registry.applyServerTruth(favourited: ["artist-1"], observed: ["artist-1", "artist-2"])
        XCTAssertEqual(registry.favourites, ["artist-1"])

        // A previously favourited item removed on the server falls back to false
        // when it carries no pending intent.
        registry.applyServerTruth(favourited: [], observed: ["artist-1"])
        XCTAssertFalse(registry.isFavourite("artist-1"))
    }

    func testApplyPendingSeedsOptimisticStateFromOutbox() {
        var registry = FavouriteRegistry()
        registry.applyPending(["song-1": true, "album-1": false])
        XCTAssertEqual(registry.favourites, ["song-1"])

        // Seeded intent still wins over server truth until it reconciles.
        registry.applyServerTruth(favourited: ["album-1"], observed: ["song-1", "album-1"])
        XCTAssertEqual(registry.favourites, ["song-1"])
    }

    func testReplacePendingKeepsEffectiveFavouritesButDropsOverride() {
        var registry = FavouriteRegistry()
        registry.setDesired("album-1", true)
        registry.replacePending([:]) // mutation reconciled, nothing left pending
        XCTAssertTrue(registry.isFavourite("album-1"), "Effective like is retained")

        // With the override gone, server truth is now authoritative again.
        registry.applyServerTruth(favourited: [], observed: ["album-1"])
        XCTAssertFalse(registry.isFavourite("album-1"))
    }
}
