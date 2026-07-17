import GRDB
import XCTest
@testable import JellyfinAudio

final class LibraryStoreTests: XCTestCase {
    func testInitializationCreatesSchemaAndMigrationIsIdempotent() async throws {
        let databaseURL = temporaryDatabaseURL()
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let album = Album(
            id: "album-a",
            name: "Synthetic Album A",
            artist: "Synthetic Artist A",
            productionYear: 2024,
            imageTag: "image-a"
        )

        let firstStore = try SQLiteLibraryStore(databaseURL: databaseURL)
        try await firstStore.replaceAlbums([album], scope: scope, libraryID: "library-a")
        let connectionSettings = try await firstStore.connectionSettings()
        XCTAssertEqual(
            connectionSettings,
            SQLiteLibraryStore.ConnectionSettings(
                journalMode: "wal",
                foreignKeysEnabled: true,
                busyTimeoutMilliseconds: 5_000
            )
        )

        let secondStore = try SQLiteLibraryStore(databaseURL: databaseURL)
        let cached = try await secondStore.cachedAlbums(scope: scope, libraryID: "library-a")
        XCTAssertEqual(cached, [album])

        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let tableNames = try await inspectionQueue.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        XCTAssertTrue(tableNames.contains("library_scopes"))
        XCTAssertTrue(tableNames.contains("cached_artists"))
        XCTAssertTrue(tableNames.contains("cached_albums"))
        XCTAssertTrue(tableNames.contains("grdb_migrations"))

        let appliedMigrations = try await inspectionQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM grdb_migrations")
        }
        XCTAssertEqual(appliedMigrations, 1)
        let foreignKeyViolationCount = try await inspectionQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count
        }
        XCTAssertEqual(foreignKeyViolationCount, 0)
    }

    func testFailedMigrationRollsBackSchemaAndData() async throws {
        enum SyntheticMigrationError: Error { case expected }

        let databaseURL = temporaryDatabaseURL()
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let sentinel = album(id: "sentinel", name: "Synthetic Sentinel")
        let initialStore = try SQLiteLibraryStore(databaseURL: databaseURL)
        try await initialStore.replaceAlbums([sentinel], scope: scope, libraryID: "library-a")

        XCTAssertThrowsError(
            try SQLiteLibraryStore(databaseURL: databaseURL) { migrator in
                migrator.registerMigration("002_synthetic_failure") { database in
                    try database.execute(sql: "CREATE TABLE should_roll_back (value TEXT NOT NULL)")
                    try database.execute(sql: "DELETE FROM cached_albums")
                    throw SyntheticMigrationError.expected
                }
            }
        ) { error in
            guard case SyntheticMigrationError.expected = error else {
                return XCTFail("Unexpected migration error type: \(type(of: error))")
            }
        }

        let recoveredStore = try SQLiteLibraryStore(databaseURL: databaseURL)
        let recoveredAlbums = try await recoveredStore.cachedAlbums(scope: scope, libraryID: "library-a")
        XCTAssertEqual(recoveredAlbums, [sentinel])
        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let rolledBackTableCount = try await inspectionQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'should_roll_back'"
            )
        }
        XCTAssertEqual(rolledBackTableCount, 0)
        let appliedMigrations = try await inspectionQueue.read { database in
            try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        XCTAssertEqual(appliedMigrations, ["001_create_library_metadata_cache"])
    }

    func testCacheIsIsolatedByServerAccountAndLibrary() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        let firstScope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let otherAccount = LibraryScope(serverID: "server-a", accountID: "account-b")
        let otherServer = LibraryScope(serverID: "server-b", accountID: "account-a")
        let firstAlbum = album(id: "shared-id", name: "Synthetic First")
        let accountAlbum = album(id: "shared-id", name: "Synthetic Account")
        let serverAlbum = album(id: "shared-id", name: "Synthetic Server")
        let libraryAlbum = album(id: "shared-id", name: "Synthetic Library")

        try await store.replaceAlbums([firstAlbum], scope: firstScope, libraryID: "library-a")
        try await store.replaceAlbums([accountAlbum], scope: otherAccount, libraryID: "library-a")
        try await store.replaceAlbums([serverAlbum], scope: otherServer, libraryID: "library-a")
        try await store.replaceAlbums([libraryAlbum], scope: firstScope, libraryID: "library-b")
        try await store.storeSearchMetadata(
            artists: [Artist(id: "shared-artist", name: "Synthetic First Artist", imageTag: nil)],
            albums: [],
            scope: firstScope,
            libraryID: "library-a"
        )
        try await store.storeSearchMetadata(
            artists: [Artist(id: "shared-artist", name: "Synthetic Account Artist", imageTag: nil)],
            albums: [],
            scope: otherAccount,
            libraryID: "library-a"
        )

        let firstCached = try await store.cachedAlbums(scope: firstScope, libraryID: "library-a")
        let accountCached = try await store.cachedAlbums(scope: otherAccount, libraryID: "library-a")
        let serverCached = try await store.cachedAlbums(scope: otherServer, libraryID: "library-a")
        let libraryCached = try await store.cachedAlbums(scope: firstScope, libraryID: "library-b")
        let globalCached = try await store.cachedAlbums(scope: firstScope, libraryID: nil)
        let firstArtistSearch = try await store.searchMusic(
            query: "artist",
            scope: firstScope,
            libraryID: "library-a"
        )
        let accountArtistSearch = try await store.searchMusic(
            query: "artist",
            scope: otherAccount,
            libraryID: "library-a"
        )
        XCTAssertEqual(firstCached, [firstAlbum])
        XCTAssertEqual(accountCached, [accountAlbum])
        XCTAssertEqual(serverCached, [serverAlbum])
        XCTAssertEqual(libraryCached, [libraryAlbum])
        XCTAssertEqual(globalCached, [])
        XCTAssertEqual(firstArtistSearch.artists.map(\.name), ["Synthetic First Artist"])
        XCTAssertEqual(accountArtistSearch.artists.map(\.name), ["Synthetic Account Artist"])
    }

    func testGlobalLibraryUsesNonNullScopeKey() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        try await store.replaceAlbums(
            [album(id: "global-album", name: "Synthetic Global")],
            scope: scope,
            libraryID: nil
        )

        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let storedScopes = try await inspectionQueue.read { database in
            try String.fetchAll(database, sql: "SELECT library_scope FROM library_scopes")
        }
        XCTAssertEqual(storedScopes, ["global"])
        let nullScopeCount = try await inspectionQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM library_scopes WHERE library_scope IS NULL")
        }
        XCTAssertEqual(nullScopeCount, 0)
    }

    func testReplaceRemovesStaleRowsAndMalformedRowsAreSkipped() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let staleAlbum = album(id: "stale", name: "Synthetic Stale")
        let currentAlbum = album(id: "current", name: "Synthetic Current")

        try await store.replaceAlbums([staleAlbum], scope: scope, libraryID: "library-a")
        try await store.replaceAlbums([currentAlbum], scope: scope, libraryID: "library-a")

        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let mismatchedPayload = try JSONEncoder().encode(album(id: "payload-id", name: "Synthetic Mismatch"))
        try await inspectionQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO cached_albums
                        (server_id, account_id, library_scope, item_id, payload)
                    VALUES (?, ?, ?, ?, ?), (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "server-a", "account-a", "library:library-a", "malformed", Data([0x00]),
                    "server-a", "account-a", "library:library-a", "row-id", mismatchedPayload,
                ]
            )
        }

        let cachedAlbums = try await store.cachedAlbums(scope: scope, libraryID: "library-a")
        XCTAssertEqual(cachedAlbums, [currentAlbum])
    }

    func testReplaceAlbumsIsAtomicWhenAWriteFails() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let sentinel = album(id: "sentinel", name: "Synthetic Sentinel")
        try await store.replaceAlbums([sentinel], scope: scope, libraryID: "library-a")

        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        try await inspectionQueue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER reject_synthetic_album
                BEFORE INSERT ON cached_albums
                WHEN NEW.item_id = 'reject'
                BEGIN
                    SELECT RAISE(ABORT, 'synthetic rejection');
                END
                """)
        }

        do {
            try await store.replaceAlbums(
                [
                    album(id: "accepted", name: "Synthetic Accepted"),
                    album(id: "reject", name: "Synthetic Rejected"),
                ],
                scope: scope,
                libraryID: "library-a"
            )
            XCTFail("Expected the synthetic trigger to reject the replacement")
        } catch {
            // The exact SQLite error is incidental; the rollback is asserted below.
        }

        let cachedAlbums = try await store.cachedAlbums(scope: scope, libraryID: "library-a")
        XCTAssertEqual(cachedAlbums, [sentinel])
    }

    func testCachedAlbumsAndSearchUseDeterministicOrdering() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let albums = [
            album(id: "z", name: "Écho", artist: "Synthetic B"),
            album(id: "b", name: "echo", artist: "Synthetic A"),
            album(id: "a", name: "echo", artist: "Synthetic A"),
            album(id: "other", name: "Synthetic Other", artist: "Synthetic C"),
        ]
        let artists = [
            Artist(id: "z", name: "Écho Artist", imageTag: nil),
            Artist(id: "b", name: "echo artist", imageTag: nil),
            Artist(id: "a", name: "echo artist", imageTag: nil),
        ]

        try await store.replaceAlbums(albums, scope: scope, libraryID: "library-a")
        try await store.storeSearchMetadata(
            artists: artists,
            albums: [],
            scope: scope,
            libraryID: "library-a"
        )

        let cachedAlbumIDs = try await store.cachedAlbums(scope: scope, libraryID: "library-a").map(\.id)
        XCTAssertEqual(cachedAlbumIDs, ["a", "b", "z", "other"])
        let search = try await store.searchMusic(query: "  ECHO  ", scope: scope, libraryID: "library-a")
        XCTAssertEqual(search.artists.map(\.id), ["a", "b", "z"])
        XCTAssertEqual(search.albums.map(\.id), ["a", "b", "z"])
        XCTAssertFalse(search.hasMore)
        XCTAssertEqual(search.nextStartIndex, 6)
    }

    func testSearchWorksFromCacheOnlyAndMatchesAlbumArtist() async throws {
        let databaseURL = temporaryDatabaseURL()
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let firstLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        try await firstLaunch.storeSearchMetadata(
            artists: [Artist(id: "artist-a", name: "Synthetic Aurora", imageTag: nil)],
            albums: [album(id: "album-a", name: "Synthetic Record", artist: "Synthetic Aurora")],
            scope: scope,
            libraryID: nil
        )

        let repeatLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        let result = try await repeatLaunch.searchMusic(query: "aurora", scope: scope, libraryID: nil)

        XCTAssertEqual(result.artists.map(\.id), ["artist-a"])
        XCTAssertEqual(result.albums.map(\.id), ["album-a"])
        let missing = try await repeatLaunch.searchMusic(query: "missing", scope: scope, libraryID: nil)
        XCTAssertEqual(missing, MusicSearchPage(artists: [], albums: [], hasMore: false, nextStartIndex: 0))
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("metadata.sqlite")
    }

    private func album(
        id: String,
        name: String,
        artist: String = "Synthetic Artist"
    ) -> Album {
        Album(id: id, name: name, artist: artist, productionYear: 2024, imageTag: nil)
    }
}
