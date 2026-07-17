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
        XCTAssertTrue(tableNames.contains("home_shelf_snapshots"))
        XCTAssertTrue(tableNames.contains("grdb_migrations"))

        let appliedMigrations = try await inspectionQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM grdb_migrations")
        }
        XCTAssertEqual(appliedMigrations, 2)
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
                migrator.registerMigration("003_synthetic_failure") { database in
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
        XCTAssertEqual(
            appliedMigrations,
            ["001_create_library_metadata_cache", "002_create_home_shelf_snapshots"]
        )
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

    func testDuplicateDisplayNamesRetainDistinctStableIdentities() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let artists = [
            Artist(id: "artist-001", name: "Synthetic Namesake", imageTag: "art-001"),
            Artist(id: "artist-002", name: "Synthetic Namesake", imageTag: "art-002"),
        ]
        let albums = [
            Album(
                id: "album-001",
                name: "Synthetic Namesake Album",
                artist: "Synthetic Namesake",
                productionYear: 2001,
                imageTag: "album-art-001"
            ),
            Album(
                id: "album-002",
                name: "Synthetic Namesake Album",
                artist: "Synthetic Namesake",
                productionYear: 2002,
                imageTag: "album-art-002"
            ),
        ]

        try await store.storeSearchMetadata(
            artists: artists,
            albums: albums,
            scope: scope,
            libraryID: "library-a"
        )

        let result = try await store.searchMusic(
            query: "namesake",
            scope: scope,
            libraryID: "library-a"
        )
        XCTAssertEqual(result.artists.map(\.id), ["artist-001", "artist-002"])
        XCTAssertEqual(result.albums.map(\.id), ["album-001", "album-002"])
        XCTAssertEqual(result.albums.map(\.productionYear), [2001, 2002])
    }

    func testSameItemIdentitiesRemainIsolatedAcrossServerAccountAndLibraryScopes() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        let primaryScope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let otherAccountScope = LibraryScope(serverID: "server-a", accountID: "account-b")
        let otherServerScope = LibraryScope(serverID: "server-b", accountID: "account-a")
        let scopedAlbums: [(LibraryScope, String, Album)] = [
            (primaryScope, "library-a", album(id: "shared-album", name: "Synthetic Primary")),
            (otherAccountScope, "library-a", album(id: "shared-album", name: "Synthetic Other Account")),
            (otherServerScope, "library-a", album(id: "shared-album", name: "Synthetic Other Server")),
            (primaryScope, "library-b", album(id: "shared-album", name: "Synthetic Other Library")),
        ]

        for (scope, libraryID, scopedAlbum) in scopedAlbums {
            try await store.replaceAlbums([scopedAlbum], scope: scope, libraryID: libraryID)
        }

        try await store.replaceAlbums(
            [album(id: "shared-album", name: "Synthetic Primary Refreshed")],
            scope: primaryScope,
            libraryID: "library-a"
        )

        let primaryNames = try await store.cachedAlbums(scope: primaryScope, libraryID: "library-a").map(\.name)
        let otherAccountNames = try await store.cachedAlbums(
            scope: otherAccountScope,
            libraryID: "library-a"
        ).map(\.name)
        let otherServerNames = try await store.cachedAlbums(
            scope: otherServerScope,
            libraryID: "library-a"
        ).map(\.name)
        let otherLibraryNames = try await store.cachedAlbums(
            scope: primaryScope,
            libraryID: "library-b"
        ).map(\.name)
        XCTAssertEqual(primaryNames, ["Synthetic Primary Refreshed"])
        XCTAssertEqual(otherAccountNames, ["Synthetic Other Account"])
        XCTAssertEqual(otherServerNames, ["Synthetic Other Server"])
        XCTAssertEqual(otherLibraryNames, ["Synthetic Other Library"])
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

    func testInvalidDomainValuesAreExcludedBeforeWritesAndValidSiblingsPersist() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let validArtist = Artist(id: "valid-artist", name: "Synthetic Valid Artist", imageTag: nil)
        let validAlbum = album(id: "valid-album", name: "Synthetic Valid Album")
        let invalidArtists = [
            Artist(id: "  ", name: "Synthetic Missing Identity", imageTag: nil),
            Artist(id: "invalid-artist", name: "\n\t", imageTag: nil),
        ]
        let invalidAlbums = [
            album(id: "", name: "Synthetic Missing Identity"),
            album(id: "invalid-name", name: "   "),
            album(id: "invalid-artist-name", name: "Synthetic Invalid Artist", artist: "\n"),
        ]

        try await store.storeSearchMetadata(
            artists: [validArtist] + invalidArtists,
            albums: [validAlbum] + invalidAlbums,
            scope: scope,
            libraryID: "library-a"
        )

        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let storedCounts = try await inspectionQueue.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cached_artists") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cached_albums") ?? -1
            )
        }
        XCTAssertEqual(storedCounts.0, 1)
        XCTAssertEqual(storedCounts.1, 1)
        let search = try await store.searchMusic(query: "valid", scope: scope, libraryID: "library-a")
        XCTAssertEqual(search.artists, [validArtist])
        XCTAssertEqual(search.albums, [validAlbum])
    }

    func testMalformedAndIdentityMismatchedStoredPayloadsAreSkippedWithoutCorruptingValidRows() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let validArtist = Artist(id: "valid-artist", name: "Synthetic Valid Sibling Artist", imageTag: nil)
        let validAlbum = album(id: "valid-album", name: "Synthetic Valid Sibling")
        try await store.replaceAlbums([validAlbum], scope: scope, libraryID: "library-a")
        try await store.storeSearchMetadata(
            artists: [validArtist],
            albums: [],
            scope: scope,
            libraryID: "library-a"
        )

        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let identityMismatch = try JSONEncoder().encode(
            album(id: "payload-identity", name: "Synthetic Identity Mismatch")
        )
        let invalidDecodedValue = try JSONEncoder().encode(
            album(id: "invalid-decoded", name: "  ")
        )
        let invalidDecodedArtist = try JSONEncoder().encode(
            Artist(id: "invalid-artist", name: "\n", imageTag: nil)
        )
        let partialRecord = Data(#"{"id":"partial","name":"Synthetic Partial"}"#.utf8)
        try await inspectionQueue.write { database in
            for (itemID, payload) in [
                ("not-json", Data([0xFF, 0x00, 0x7F])),
                ("row-identity", identityMismatch),
                ("invalid-decoded", invalidDecodedValue),
                ("partial", partialRecord),
            ] {
                try database.execute(
                    sql: """
                        INSERT INTO cached_albums
                            (server_id, account_id, library_scope, item_id, payload)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: ["server-a", "account-a", "library:library-a", itemID, payload]
                )
            }
            try database.execute(
                sql: """
                    INSERT INTO cached_artists
                        (server_id, account_id, library_scope, item_id, payload)
                    VALUES (?, ?, ?, ?, ?), (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "server-a", "account-a", "library:library-a", "not-json-artist", Data([0x00]),
                    "server-a", "account-a", "library:library-a", "invalid-artist", invalidDecodedArtist,
                ]
            )
        }

        let cachedAlbums = try await store.cachedAlbums(scope: scope, libraryID: "library-a")
        XCTAssertEqual(cachedAlbums, [validAlbum])
        let search = try await store.searchMusic(query: "synthetic", scope: scope, libraryID: "library-a")
        XCTAssertEqual(search.artists, [validArtist])
        XCTAssertEqual(search.albums, [validAlbum])
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

    func testUnicodeAndNormalizationSensitiveTextRoundTripsAndSearchesDeterministically() async throws {
        let databaseURL = temporaryDatabaseURL()
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let composedArtist = Artist(id: "artist-composed", name: "Caf\u{00E9} 東京", imageTag: nil)
        let decomposedArtist = Artist(id: "artist-decomposed", name: "Cafe\u{0301} 東京", imageTag: nil)
        let fullWidthAlbum = Album(
            id: "album-full-width",
            name: "Ｓｙｎｔｈｅｔｉｃ 星",
            artist: "Fjo\u{0308}ra Synth Δ",
            productionYear: 2024,
            imageTag: nil
        )
        let firstLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        try await firstLaunch.storeSearchMetadata(
            artists: [decomposedArtist, composedArtist],
            albums: [fullWidthAlbum],
            scope: scope,
            libraryID: "library-a"
        )

        let repeatLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        let accentSearch = try await repeatLaunch.searchMusic(
            query: "CAFE 東京",
            scope: scope,
            libraryID: "library-a"
        )
        XCTAssertEqual(Set(accentSearch.artists), Set([composedArtist, decomposedArtist]))
        let widthSearch = try await repeatLaunch.searchMusic(
            query: "synthetic 星",
            scope: scope,
            libraryID: "library-a"
        )
        XCTAssertEqual(widthSearch.albums, [fullWidthAlbum])
        let artistSearch = try await repeatLaunch.searchMusic(
            query: "FJÖRA SYNTH Δ",
            scope: scope,
            libraryID: "library-a"
        )
        XCTAssertEqual(artistSearch.albums, [fullWidthAlbum])
    }

    func testMissingArtworkAndOptionalMetadataRoundTripWithoutInventedValues() async throws {
        let databaseURL = temporaryDatabaseURL()
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let artistWithoutArtwork = Artist(
            id: "artist-no-artwork",
            name: "Synthetic Unillustrated Artist",
            imageTag: nil
        )
        let albumWithoutOptionalMetadata = Album(
            id: "album-no-optionals",
            name: "Synthetic Unillustrated Album",
            artist: "Synthetic Unillustrated Artist",
            productionYear: nil,
            imageTag: nil
        )
        let firstLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        try await firstLaunch.storeSearchMetadata(
            artists: [artistWithoutArtwork],
            albums: [albumWithoutOptionalMetadata],
            scope: scope,
            libraryID: "library-a"
        )

        let repeatLaunch = try SQLiteLibraryStore(databaseURL: databaseURL)
        let search = try await repeatLaunch.searchMusic(
            query: "unillustrated",
            scope: scope,
            libraryID: "library-a"
        )
        XCTAssertEqual(search.artists, [artistWithoutArtwork])
        XCTAssertEqual(search.albums, [albumWithoutOptionalMetadata])
        XCTAssertNil(search.artists.first?.imageTag)
        XCTAssertNil(search.albums.first?.imageTag)
        XCTAssertNil(search.albums.first?.productionYear)
    }

    func testRepeatedFixtureRefreshIsIdempotentAndDoesNotCreateDuplicateRows() async throws {
        let databaseURL = temporaryDatabaseURL()
        let store = try SQLiteLibraryStore(databaseURL: databaseURL)
        let scope = LibraryScope(serverID: "server-a", accountID: "account-a")
        let firstVersion = [
            album(id: "album-a", name: "Synthetic Album A"),
            album(id: "album-b", name: "Synthetic Album B"),
        ]
        let refreshedVersion = [
            album(id: "album-a", name: "Synthetic Album A Refreshed"),
            album(id: "album-b", name: "Synthetic Album B"),
        ]

        try await store.replaceAlbums(firstVersion, scope: scope, libraryID: "library-a")
        try await store.replaceAlbums(refreshedVersion, scope: scope, libraryID: "library-a")
        try await store.replaceAlbums(refreshedVersion, scope: scope, libraryID: "library-a")
        try await store.storeSearchMetadata(
            artists: [
                Artist(id: "artist-a", name: "Synthetic Artist Refreshed", imageTag: nil),
                Artist(id: "artist-a", name: "Synthetic Artist Refreshed", imageTag: nil),
            ],
            albums: refreshedVersion + refreshedVersion,
            scope: scope,
            libraryID: "library-a"
        )

        let cachedAlbums = try await store.cachedAlbums(scope: scope, libraryID: "library-a")
        XCTAssertEqual(cachedAlbums, refreshedVersion)
        let inspectionQueue = try DatabaseQueue(path: databaseURL.path)
        let rowCounts = try await inspectionQueue.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cached_artists") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM cached_albums") ?? -1
            )
        }
        XCTAssertEqual(rowCounts.0, 1)
        XCTAssertEqual(rowCounts.1, 2)
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
