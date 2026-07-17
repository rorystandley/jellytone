import Foundation
import GRDB

/// The SQLite-backed metadata cache. Database rows remain private to this type;
/// callers exchange only stable domain values through `LibraryStoring`.
final class SQLiteLibraryStore: LibraryStoring, @unchecked Sendable {
    struct ConnectionSettings: Equatable {
        let journalMode: String
        let foreignKeysEnabled: Bool
        let busyTimeoutMilliseconds: Int
    }

    private static let globalLibraryScope = "global"

    private let databaseQueue: DatabaseQueue

    init(
        databaseURL: URL,
        registerAdditionalMigrations: ((inout DatabaseMigrator) -> Void)? = nil
    ) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        var migrator = Self.makeMigrator()
        registerAdditionalMigrations?(&migrator)
        try migrator.migrate(databaseQueue)
    }

    /// Read-only operational evidence used by migration/configuration tests.
    /// It contains no server, account, or library metadata.
    func connectionSettings() async throws -> ConnectionSettings {
        try await databaseQueue.read { database in
            ConnectionSettings(
                journalMode: try String.fetchOne(database, sql: "PRAGMA journal_mode") ?? "",
                foreignKeysEnabled: try Int.fetchOne(database, sql: "PRAGMA foreign_keys") == 1,
                busyTimeoutMilliseconds: try Int.fetchOne(database, sql: "PRAGMA busy_timeout") ?? 0
            )
        }
    }

    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album] {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_albums
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )

            return rows.compactMap(Self.album(from:)).sorted(by: Self.albumPrecedes)
        }
    }

    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let validAlbums = albums.filter(Self.isValid)

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(
                sql: """
                    DELETE FROM cached_albums
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            for album in validAlbums {
                try Self.upsert(album, scope: scope, libraryScope: libraryScope, in: database)
            }
        }
    }

    func cachedHomeShelfSnapshot(
        scope: LibraryScope,
        libraryID: String?
    ) async throws -> HomeShelfSnapshot? {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            guard let payload: Data = try Data.fetchOne(
                database,
                sql: """
                    SELECT payload
                    FROM home_shelf_snapshots
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) else {
                return nil
            }
            return Self.homeShelfSnapshot(from: payload)
        }
    }

    func replaceHomeShelfSnapshot(
        _ snapshot: HomeShelfSnapshot,
        scope: LibraryScope,
        libraryID: String?
    ) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let payload = try JSONEncoder().encode(snapshot)

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(
                sql: """
                    INSERT INTO home_shelf_snapshots
                        (server_id, account_id, library_scope, payload)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT (server_id, account_id, library_scope)
                    DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope, payload]
            )
        }
    }

    func storeSearchMetadata(
        artists: [Artist],
        albums: [Album],
        scope: LibraryScope,
        libraryID: String?
    ) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let validArtists = artists.filter(Self.isValid)
        let validAlbums = albums.filter(Self.isValid)

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            for artist in validArtists {
                try Self.upsert(artist, scope: scope, libraryScope: libraryScope, in: database)
            }
            for album in validAlbums {
                try Self.upsert(album, scope: scope, libraryScope: libraryScope, in: database)
            }
        }
    }

    func searchMusic(query: String, scope: LibraryScope, libraryID: String?) async throws -> MusicSearchPage {
        let normalizedQuery = Self.normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedQuery.isEmpty else {
            return MusicSearchPage(artists: [], albums: [], hasMore: false, nextStartIndex: 0)
        }

        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            let artistRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_artists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            let albumRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_albums
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )

            let artists = artistRows
                .compactMap(Self.artist(from:))
                .filter { Self.normalized($0.name).contains(normalizedQuery) }
                .sorted(by: Self.artistPrecedes)
            let albums = albumRows
                .compactMap(Self.album(from:))
                .filter {
                    Self.normalized($0.name).contains(normalizedQuery)
                        || Self.normalized($0.artist).contains(normalizedQuery)
                }
                .sorted(by: Self.albumPrecedes)

            return MusicSearchPage(
                artists: artists,
                albums: albums,
                hasMore: false,
                nextStartIndex: artists.count + albums.count
            )
        }
    }
}

private extension SQLiteLibraryStore {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("001_create_library_metadata_cache") { database in
            try database.execute(sql: """
                CREATE TABLE library_scopes (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope)
                ) WITHOUT ROWID;

                CREATE TABLE cached_artists (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope, item_id),
                    FOREIGN KEY (server_id, account_id, library_scope)
                        REFERENCES library_scopes (server_id, account_id, library_scope)
                        ON DELETE CASCADE
                ) WITHOUT ROWID;

                CREATE TABLE cached_albums (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope, item_id),
                    FOREIGN KEY (server_id, account_id, library_scope)
                        REFERENCES library_scopes (server_id, account_id, library_scope)
                        ON DELETE CASCADE
                ) WITHOUT ROWID;
                """)
        }
        migrator.registerMigration("002_create_home_shelf_snapshots") { database in
            try database.execute(sql: """
                CREATE TABLE home_shelf_snapshots (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope),
                    FOREIGN KEY (server_id, account_id, library_scope)
                        REFERENCES library_scopes (server_id, account_id, library_scope)
                        ON DELETE CASCADE
                ) WITHOUT ROWID;
                """)
        }
        return migrator
    }

    static func libraryScope(for libraryID: String?) -> String {
        guard let libraryID else { return globalLibraryScope }
        return "library:\(libraryID)"
    }

    static func ensureScope(_ scope: LibraryScope, libraryScope: String, in database: Database) throws {
        try database.execute(
            sql: """
                INSERT OR IGNORE INTO library_scopes (server_id, account_id, library_scope)
                VALUES (?, ?, ?)
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope]
        )
    }

    static func upsert(_ artist: Artist, scope: LibraryScope, libraryScope: String, in database: Database) throws {
        let payload = try JSONEncoder().encode(artist)
        try database.execute(
            sql: """
                INSERT INTO cached_artists (server_id, account_id, library_scope, item_id, payload)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (server_id, account_id, library_scope, item_id)
                DO UPDATE SET payload = excluded.payload
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope, artist.id, payload]
        )
    }

    static func upsert(_ album: Album, scope: LibraryScope, libraryScope: String, in database: Database) throws {
        let payload = try JSONEncoder().encode(album)
        try database.execute(
            sql: """
                INSERT INTO cached_albums (server_id, account_id, library_scope, item_id, payload)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (server_id, account_id, library_scope, item_id)
                DO UPDATE SET payload = excluded.payload
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope, album.id, payload]
        )
    }

    static func artist(from row: Row) -> Artist? {
        guard let itemID: String = row["item_id"],
              let payload: Data = row["payload"],
              let artist = try? JSONDecoder().decode(Artist.self, from: payload),
              artist.id == itemID,
              isValid(artist)
        else { return nil }
        return artist
    }

    static func album(from row: Row) -> Album? {
        guard let itemID: String = row["item_id"],
              let payload: Data = row["payload"],
              let album = try? JSONDecoder().decode(Album.self, from: payload),
              album.id == itemID,
              isValid(album)
        else { return nil }
        return album
    }

    static func homeShelfSnapshot(from payload: Data) -> HomeShelfSnapshot? {
        try? JSONDecoder().decode(HomeShelfSnapshot.self, from: payload)
    }

    static func isValid(_ artist: Artist) -> Bool {
        !artist.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !artist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isValid(_ album: Album) -> Bool {
        !album.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !album.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !album.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func artistPrecedes(_ lhs: Artist, _ rhs: Artist) -> Bool {
        let lhsName = normalized(lhs.name)
        let rhsName = normalized(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }

    static func albumPrecedes(_ lhs: Album, _ rhs: Album) -> Bool {
        let lhsName = normalized(lhs.name)
        let rhsName = normalized(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        let lhsArtist = normalized(lhs.artist)
        let rhsArtist = normalized(rhs.artist)
        if lhsArtist != rhsArtist { return lhsArtist < rhsArtist }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.artist != rhs.artist { return lhs.artist < rhs.artist }
        return lhs.id < rhs.id
    }
}
