import GRDB
import XCTest
@testable import Jellytone

@MainActor
final class HomeShelfPersistenceTests: XCTestCase {
    func testSnapshotRoundTripsAcrossLaunchesWithOrderingAndOptionalMetadata() async throws {
        let databaseURL = temporaryDatabaseURL()
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let snapshot = HomeShelfSnapshot(
            version: 1,
            recentlyAddedAlbums: [Album(id: "album-first", name: "Unicode Café first", artist: "Artist", productionYear: nil, imageTag: nil)],
            recentlyPlayedTracks: [Track(id: "track-first", name: "Track first", artist: "Artist", album: "Album", index: nil, disc: nil, durationTicks: nil)],
            favouriteArtists: [Artist(id: "artist-first", name: "Favourite Artist", imageTag: "tag-first")]
        )

        let firstLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        try await firstLaunch.replaceHomeShelfSnapshot(snapshot, scope: scope, libraryID: "library-a")
        let repeatLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)

        let cached = try await repeatLaunch.cachedHomeShelfSnapshot(scope: scope, libraryID: "library-a")
        XCTAssertEqual(cached, snapshot)
    }

    func testSnapshotsPersistedBeforeMadeForYouShelfStillDecode() throws {
        // Payload shape from before the madeForYouPlaylists and
        // favouriteArtists shelves existed — older caches must stay valid,
        // decoding to empty shelves.
        let legacyPayload = Data("""
            {"version":1,
             "recentlyAddedAlbums":[{"id":"album-a","name":"Synthetic Album","artist":"Synthetic Artist"}],
             "recentlyPlayedTracks":[]}
            """.utf8)
        let decoded = try JSONDecoder().decode(HomeShelfSnapshot.self, from: legacyPayload)
        XCTAssertEqual(decoded.recentlyAddedAlbums.first?.id, "album-a")
        XCTAssertEqual(decoded.madeForYouPlaylists, [])
        XCTAssertEqual(decoded.favouriteArtists, [])
    }

    func testReplacementIsAtomicAndScopedByServerAccountAndLibrary() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let primary = LibraryScope(serverID: "server-a", accountID: "account-a")
        let otherAccount = LibraryScope(serverID: "server-a", accountID: "account-b")
        let otherServer = LibraryScope(serverID: "server-b", accountID: "account-a")
        let original = fixture(version: 1, suffix: "original")
        try await store.replaceHomeShelfSnapshot(original, scope: primary, libraryID: "library-a")
        try await store.replaceHomeShelfSnapshot(fixture(version: 1, suffix: "account"), scope: otherAccount, libraryID: "library-a")
        try await store.replaceHomeShelfSnapshot(fixture(version: 1, suffix: "server"), scope: otherServer, libraryID: "library-a")
        try await store.replaceHomeShelfSnapshot(fixture(version: 1, suffix: "library"), scope: primary, libraryID: "library-b")

        let queue = try DatabaseQueue(path: databaseURL.path)
        try await queue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER reject_home_snapshot
                BEFORE INSERT ON home_shelf_snapshots
                WHEN 1
                BEGIN SELECT RAISE(ABORT, 'synthetic rejection'); END
                """)
        }
        do {
            try await store.replaceHomeShelfSnapshot(
                fixture(version: 1, suffix: "reject"), scope: primary, libraryID: "library-a"
            )
            XCTFail("Expected the synthetic trigger to reject replacement")
        } catch {}
        let retained = try await store.cachedHomeShelfSnapshot(scope: primary, libraryID: "library-a")
        let accountSnapshot = try await store.cachedHomeShelfSnapshot(scope: otherAccount, libraryID: "library-a")
        let serverSnapshot = try await store.cachedHomeShelfSnapshot(scope: otherServer, libraryID: "library-a")
        let librarySnapshot = try await store.cachedHomeShelfSnapshot(scope: primary, libraryID: "library-b")
        XCTAssertEqual(retained, original)
        XCTAssertEqual(accountSnapshot?.recentlyAddedAlbums.first?.id, "album-account")
        XCTAssertEqual(serverSnapshot?.recentlyAddedAlbums.first?.id, "album-server")
        XCTAssertEqual(librarySnapshot?.recentlyAddedAlbums.first?.id, "album-library")
    }

    func testMalformedSnapshotIsIgnoredWithoutCorruptingOtherScopes() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let validScope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let malformedScope = LibraryScope(serverID: "server-b", accountID: "account-b")
        let valid = fixture(version: 1, suffix: "valid")
        try await store.replaceHomeShelfSnapshot(valid, scope: validScope, libraryID: "library-a")

        let queue = try DatabaseQueue(path: databaseURL.path)
        try await queue.write { database in
            try database.execute(sql: "INSERT INTO library_scopes VALUES (?, ?, ?)", arguments: ["server-b", "account-b", "library:library-a"])
            try database.execute(sql: "INSERT INTO home_shelf_snapshots VALUES (?, ?, ?, ?)", arguments: ["server-b", "account-b", "library:library-a", Data([0x00, 0xFF])])
        }
        let malformed = try await store.cachedHomeShelfSnapshot(scope: malformedScope, libraryID: "library-a")
        let retained = try await store.cachedHomeShelfSnapshot(scope: validScope, libraryID: "library-a")
        XCTAssertNil(malformed)
        XCTAssertEqual(retained, valid)
    }

    func testFailedCacheFirstRefreshRetainsPresentedSnapshot() async throws {
        let snapshot = fixture(version: 1, suffix: "cached")
        let cacheScope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let store = HomeMemoryStore(snapshot: snapshot, scope: cacheScope, libraryID: "library-a")
        var presented: [HomeShelfSnapshot] = []

        let result = await HomeCacheRefresh.execute(
            scope: cacheScope,
            libraryID: "library-a", store: store, present: { presented.append($0) }
        ) { throw URLError(.timedOut) }

        XCTAssertEqual(presented, [snapshot])
        let retained = try await store.cachedHomeShelfSnapshot(scope: .init(serverID: "server-a", accountID: "account-a"), libraryID: "library-a")
        XCTAssertEqual(retained, snapshot)
        guard case .failure = result else { return XCTFail("Expected refresh failure") }
    }

    func testOlderRefreshCannotOverwriteNewScopeSnapshot() async throws {
        let coordinator = HomeCacheRefreshCoordinator()
        let store = HomeMemoryStore(snapshot: nil)
        let firstStarted = expectation(description: "first started")
        let releaseFirst = expectation(description: "release first")
        var presentations: [String] = []

        let first = Task { @MainActor in
            await coordinator.refresh(scope: .init(serverID: "server-a", accountID: "account-a"), libraryID: "library-a", store: store, present: { presentations.append($0.recentlyAddedAlbums[0].id) }) {
                firstStarted.fulfill()
                await fulfillment(of: [releaseFirst], timeout: 2)
                return self.fixture(version: 1, suffix: "old")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = await coordinator.refresh(scope: .init(serverID: "server-b", accountID: "account-b"), libraryID: "library-b", store: store, present: { presentations.append($0.recentlyAddedAlbums[0].id) }) {
            self.fixture(version: 1, suffix: "new")
        }
        releaseFirst.fulfill()
        _ = await first.value

        XCTAssertEqual(try second.get().recentlyAddedAlbums.first?.id, "album-new")
        XCTAssertEqual(presentations, ["album-new"])
        let oldScope = try await store.cachedHomeShelfSnapshot(scope: .init(serverID: "server-a", accountID: "account-a"), libraryID: "library-a")
        let newScope = try await store.cachedHomeShelfSnapshot(scope: .init(serverID: "server-b", accountID: "account-b"), libraryID: "library-b")
        XCTAssertNil(oldScope)
        XCTAssertEqual(newScope?.recentlyAddedAlbums.first?.id, "album-new")
    }

    private func fixture(version: Int, suffix: String) -> HomeShelfSnapshot {
        HomeShelfSnapshot(version: version, recentlyAddedAlbums: [Album(id: "album-\(suffix)", name: "Unicode Café \(suffix)", artist: "Artist", productionYear: nil, imageTag: nil)], recentlyPlayedTracks: [Track(id: "track-\(suffix)", name: "Track \(suffix)", artist: "Artist", album: "Album", index: nil, disc: nil, durationTicks: nil)])
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HomeShelfPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("metadata.sqlite")
    }
}

private actor HomeMemoryStore: LibraryStoring {
    private struct Key: Hashable {
        let scope: LibraryScope
        let libraryID: String?
    }

    private var snapshots: [Key: HomeShelfSnapshot] = [:]

    init(snapshot: HomeShelfSnapshot?, scope: LibraryScope? = nil, libraryID: String? = nil) {
        if let snapshot, let scope {
            snapshots[Key(scope: scope, libraryID: libraryID)] = snapshot
        }
    }

    func cachedHomeShelfSnapshot(scope: LibraryScope, libraryID: String?) async throws -> HomeShelfSnapshot? {
        snapshots[Key(scope: scope, libraryID: libraryID)]
    }

    func replaceHomeShelfSnapshot(_ snapshot: HomeShelfSnapshot, scope: LibraryScope, libraryID: String?) async throws {
        snapshots[Key(scope: scope, libraryID: libraryID)] = snapshot
    }
    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album] { [] }
    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws {}
    func storeSearchMetadata(artists: [Artist], albums: [Album], playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws {}
    func searchMusic(query: String, scope: LibraryScope, libraryID: String?) async throws -> MusicSearchPage { .init() }
}
