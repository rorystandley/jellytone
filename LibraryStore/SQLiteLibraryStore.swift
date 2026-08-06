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
                    ORDER BY sort_index, item_id
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )

            // Server-authoritative order: rows come back in the sequence the
            // pages were received (newest-first for the album shelf).
            return rows.compactMap(Self.album(from:))
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
            for (position, album) in validAlbums.enumerated() {
                try Self.upsert(album, sortIndex: position, scope: scope, libraryScope: libraryScope, in: database)
            }
        }
    }

    /// Appends a further page received while paginating, after the tail the
    /// cache already holds. Albums already cached keep their position (only
    /// their payload refreshes) so re-received items never jump the order.
    func appendAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let validAlbums = albums.filter(Self.isValid)
        guard !validAlbums.isEmpty else { return }

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            var nextIndex = try Int.fetchOne(
                database,
                sql: """
                    SELECT COALESCE(MAX(sort_index) + 1, 0)
                    FROM cached_albums
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for album in validAlbums {
                try Self.upsert(album, sortIndex: nextIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextIndex += 1
            }
        }
    }

    func cachedAlbumTracks(albumID: String, scope: LibraryScope, libraryID: String?) async throws -> [Track]? {
        try await detailSnapshot(containerID: "album:\(albumID)", scope: scope, libraryID: libraryID)
    }

    func replaceAlbumTracks(_ tracks: [Track], albumID: String, scope: LibraryScope, libraryID: String?) async throws {
        try await replaceDetailSnapshot(tracks, containerID: "album:\(albumID)", scope: scope, libraryID: libraryID)
    }

    func cachedPlaylistEntries(playlistID: String, scope: LibraryScope, libraryID: String?) async throws -> [PlaylistEntry]? {
        try await detailSnapshot(containerID: "playlist:\(playlistID)", scope: scope, libraryID: libraryID)
    }

    func replacePlaylistEntries(_ entries: [PlaylistEntry], playlistID: String, scope: LibraryScope, libraryID: String?) async throws {
        try await replaceDetailSnapshot(entries, containerID: "playlist:\(playlistID)", scope: scope, libraryID: libraryID)
    }

    func cachedArtistAlbums(artistID: String, scope: LibraryScope, libraryID: String?) async throws -> [Album]? {
        try await detailSnapshot(containerID: "artist-albums:\(artistID)", scope: scope, libraryID: libraryID)
    }

    func replaceArtistAlbums(_ albums: [Album], artistID: String, scope: LibraryScope, libraryID: String?) async throws {
        try await replaceDetailSnapshot(albums, containerID: "artist-albums:\(artistID)", scope: scope, libraryID: libraryID)
    }

    func cachedArtistTopTracks(artistID: String, scope: LibraryScope, libraryID: String?) async throws -> [Track]? {
        try await detailSnapshot(containerID: "artist-top-tracks:\(artistID)", scope: scope, libraryID: libraryID)
    }

    func replaceArtistTopTracks(_ tracks: [Track], artistID: String, scope: LibraryScope, libraryID: String?) async throws {
        try await replaceDetailSnapshot(tracks, containerID: "artist-top-tracks:\(artistID)", scope: scope, libraryID: libraryID)
    }

    // MARK: Playlist / genre browse caches

    func cachedPlaylists(scope: LibraryScope, libraryID: String?) async throws -> [Playlist] {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_playlists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    ORDER BY sort_index, item_id
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            return rows.compactMap(Self.playlist(from:))
        }
    }

    func replacePlaylists(_ playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let valid = playlists.filter(Self.isValid)
        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(
                sql: "DELETE FROM cached_playlists WHERE server_id = ? AND account_id = ? AND library_scope = ?",
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            for (position, playlist) in valid.enumerated() {
                try Self.upsert(playlist, sortIndex: position, scope: scope, libraryScope: libraryScope, in: database)
            }
        }
    }

    func appendPlaylists(_ playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let valid = playlists.filter(Self.isValid)
        guard !valid.isEmpty else { return }
        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            var nextIndex = try Int.fetchOne(
                database,
                sql: "SELECT COALESCE(MAX(sort_index) + 1, 0) FROM cached_playlists WHERE server_id = ? AND account_id = ? AND library_scope = ?",
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for playlist in valid {
                try Self.upsert(playlist, sortIndex: nextIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextIndex += 1
            }
        }
    }

    func cachedGenres(scope: LibraryScope, libraryID: String?) async throws -> [Genre] {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_genres
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    ORDER BY sort_index, item_id
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            return rows.compactMap(Self.genre(from:))
        }
    }

    func replaceGenres(_ genres: [Genre], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let valid = genres.filter(Self.isValid)
        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(
                sql: "DELETE FROM cached_genres WHERE server_id = ? AND account_id = ? AND library_scope = ?",
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            for (position, genre) in valid.enumerated() {
                try Self.upsert(genre, sortIndex: position, scope: scope, libraryScope: libraryScope, in: database)
            }
        }
    }

    func appendGenres(_ genres: [Genre], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let valid = genres.filter(Self.isValid)
        guard !valid.isEmpty else { return }
        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            var nextIndex = try Int.fetchOne(
                database,
                sql: "SELECT COALESCE(MAX(sort_index) + 1, 0) FROM cached_genres WHERE server_id = ? AND account_id = ? AND library_scope = ?",
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for genre in valid {
                try Self.upsert(genre, sortIndex: nextIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextIndex += 1
            }
        }
    }

    func cachedGenreAlbums(genreID: String, scope: LibraryScope, libraryID: String?) async throws -> [Album]? {
        try await detailSnapshot(containerID: "genre-albums:\(genreID)", scope: scope, libraryID: libraryID)
    }

    func replaceGenreAlbums(_ albums: [Album], genreID: String, scope: LibraryScope, libraryID: String?) async throws {
        try await replaceDetailSnapshot(albums.filter(Self.isValid), containerID: "genre-albums:\(genreID)",
                                        scope: scope, libraryID: libraryID)
    }

    func cachedGenreTracks(genreID: String, scope: LibraryScope, libraryID: String?) async throws -> [GenreTrackOccurrence]? {
        try await detailSnapshot(containerID: "genre-tracks:\(genreID)", scope: scope, libraryID: libraryID)
    }

    func replaceGenreTracks(_ occurrences: [GenreTrackOccurrence], genreID: String, scope: LibraryScope, libraryID: String?) async throws {
        try await replaceDetailSnapshot(occurrences, containerID: "genre-tracks:\(genreID)",
                                        scope: scope, libraryID: libraryID)
    }

    private func detailSnapshot<Value: Decodable & Sendable>(
        containerID: String,
        scope: LibraryScope,
        libraryID: String?
    ) async throws -> Value? {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            guard let payload: Data = try Data.fetchOne(
                database,
                sql: """
                    SELECT payload
                    FROM detail_track_snapshots
                    WHERE server_id = ? AND account_id = ? AND library_scope = ? AND container_id = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope, containerID]
            ) else { return nil }
            return try? JSONDecoder().decode(Value.self, from: payload)
        }
    }

    private func replaceDetailSnapshot<Value: Encodable & Sendable>(
        _ value: Value,
        containerID: String,
        scope: LibraryScope,
        libraryID: String?
    ) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let payload = try JSONEncoder().encode(value)
        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(
                sql: """
                    INSERT INTO detail_track_snapshots (server_id, account_id, library_scope, container_id, payload)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT (server_id, account_id, library_scope, container_id)
                    DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope, containerID, payload]
            )
        }
    }

    func downloadedTracks(scope: LibraryScope) async throws -> [DownloadedTrack] {
        try await databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM downloaded_tracks
                    WHERE server_id = ? AND account_id = ?
                    """,
                arguments: [scope.serverID, scope.accountID]
            )
            return rows.compactMap { row -> DownloadedTrack? in
                guard let itemID: String = row["item_id"],
                      let payload: Data = row["payload"],
                      let record = try? JSONDecoder().decode(DownloadedTrack.self, from: payload),
                      record.track.id == itemID else { return nil }
                return record
            }
            .sorted { $0.completedAtEpochSeconds > $1.completedAtEpochSeconds }
        }
    }

    func recordDownloadedTrack(_ record: DownloadedTrack, scope: LibraryScope) async throws {
        let payload = try JSONEncoder().encode(record)
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO downloaded_tracks (server_id, account_id, item_id, payload)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT (server_id, account_id, item_id)
                    DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [scope.serverID, scope.accountID, record.track.id, payload]
            )
        }
    }

    func removeDownloadedTrack(itemID: String, scope: LibraryScope) async throws {
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    DELETE FROM downloaded_tracks
                    WHERE server_id = ? AND account_id = ? AND item_id = ?
                    """,
                arguments: [scope.serverID, scope.accountID, itemID]
            )
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

    func cachedArtists(scope: LibraryScope, libraryID: String?) async throws -> [Artist] {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_artists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    ORDER BY sort_index, item_id
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            // Server-authoritative order: rows come back in the sequence the
            // pages were received (SortName collation for the browse list).
            return rows.compactMap(Self.artist(from:))
        }
    }

    func replaceArtists(_ artists: [Artist], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let validArtists = artists.filter(Self.isValid)

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(
                sql: """
                    DELETE FROM cached_artists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            for (position, artist) in validArtists.enumerated() {
                try Self.upsert(artist, sortIndex: position, scope: scope, libraryScope: libraryScope, in: database)
            }
        }
    }

    func appendArtists(_ artists: [Artist], scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let validArtists = artists.filter(Self.isValid)
        guard !validArtists.isEmpty else { return }

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            var nextIndex = try Int.fetchOne(
                database,
                sql: """
                    SELECT COALESCE(MAX(sort_index) + 1, 0)
                    FROM cached_artists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for artist in validArtists {
                try Self.upsert(artist, sortIndex: nextIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextIndex += 1
            }
        }
    }

    func storeSearchMetadata(
        artists: [Artist],
        albums: [Album],
        playlists: [Playlist],
        scope: LibraryScope,
        libraryID: String?
    ) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        let validArtists = artists.filter(Self.isValid)
        let validAlbums = albums.filter(Self.isValid)
        let validPlaylists = playlists.filter(Self.isValid)

        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            // Search metadata must not disturb the browse order: already-cached
            // artists/albums/playlists keep their sort_index on conflict;
            // genuinely new ones land after the current tail rather than at
            // the top.
            var nextArtistIndex = try Int.fetchOne(
                database,
                sql: """
                    SELECT COALESCE(MAX(sort_index) + 1, 0)
                    FROM cached_artists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for artist in validArtists {
                try Self.upsert(artist, sortIndex: nextArtistIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextArtistIndex += 1
            }
            var nextIndex = try Int.fetchOne(
                database,
                sql: """
                    SELECT COALESCE(MAX(sort_index) + 1, 0)
                    FROM cached_albums
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for album in validAlbums {
                try Self.upsert(album, sortIndex: nextIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextIndex += 1
            }
            var nextPlaylistIndex = try Int.fetchOne(
                database,
                sql: """
                    SELECT COALESCE(MAX(sort_index) + 1, 0)
                    FROM cached_playlists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            ) ?? 0
            for playlist in validPlaylists {
                try Self.upsert(playlist, sortIndex: nextPlaylistIndex, scope: scope, libraryScope: libraryScope, in: database)
                nextPlaylistIndex += 1
            }
        }
    }

    func searchMusic(query: String, scope: LibraryScope, libraryID: String?) async throws -> MusicSearchPage {
        let normalizedQuery = Self.normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedQuery.isEmpty else {
            return MusicSearchPage()
        }

        let libraryScope = Self.libraryScope(for: libraryID)
        // Cap local matches so a huge catalogue never dumps thousands of rows
        // into the search UI before the server merge arrives.
        let localLimit = 40
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
            let playlistRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT item_id, payload
                    FROM cached_playlists
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )
            // Track catalogue payloads are occurrences; search unique tracks.
            let trackRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT occurrence_id, ordinal, payload
                    FROM track_catalog_entries
                    WHERE server_id = ? AND account_id = ? AND library_scope = ?
                    ORDER BY ordinal
                    """,
                arguments: [scope.serverID, scope.accountID, libraryScope]
            )

            let artists = Array(
                artistRows
                    .compactMap(Self.artist(from:))
                    .filter { Self.normalized($0.name).contains(normalizedQuery) }
                    .sorted(by: Self.artistPrecedes)
                    .prefix(localLimit)
            )
            let albums = Array(
                albumRows
                    .compactMap(Self.album(from:))
                    .filter {
                        Self.normalized($0.name).contains(normalizedQuery)
                            || Self.normalized($0.artist).contains(normalizedQuery)
                    }
                    .sorted(by: Self.albumPrecedes)
                    .prefix(localLimit)
            )
            let playlists = Array(
                playlistRows
                    .compactMap(Self.playlist(from:))
                    .filter { Self.normalized($0.name).contains(normalizedQuery) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .prefix(localLimit)
            )

            var seenTrackIDs = Set<String>()
            var tracks: [Track] = []
            for occurrence in trackRows.compactMap(Self.trackOccurrence(from:)) {
                let track = occurrence.track
                guard seenTrackIDs.insert(track.id).inserted else { continue }
                let matches = Self.normalized(track.name).contains(normalizedQuery)
                    || Self.normalized(track.artist).contains(normalizedQuery)
                    || Self.normalized(track.album).contains(normalizedQuery)
                guard matches else { continue }
                tracks.append(track)
                if tracks.count >= localLimit { break }
            }

            return MusicSearchPage(
                artists: artists,
                albums: albums,
                tracks: tracks,
                playlists: playlists,
                hasMore: false,
                nextStartIndex: artists.count + albums.count + tracks.count + playlists.count
            )
        }
    }

    func cachedTrackCatalogPage(scope: LibraryScope, libraryID: String?, limit: Int) async throws -> TrackCatalogPage? {
        let libraryScope = Self.libraryScope(for: libraryID)
        return try await databaseQueue.read { database in
            guard let metadata = try Row.fetchOne(database, sql: "SELECT generation, has_more, next_start_index FROM track_catalog_metadata WHERE server_id = ? AND account_id = ? AND library_scope = ?", arguments: [scope.serverID, scope.accountID, libraryScope]) else { return nil }
            let rows = try Row.fetchAll(database, sql: "SELECT occurrence_id, ordinal, payload FROM track_catalog_entries WHERE server_id = ? AND account_id = ? AND library_scope = ? ORDER BY ordinal LIMIT ?", arguments: [scope.serverID, scope.accountID, libraryScope, min(max(limit, 1), 200)])
            let occurrences = rows.compactMap(Self.trackOccurrence(from:))
            return TrackCatalogPage(occurrences: occurrences, hasMore: (metadata["has_more"] as Int) == 1, nextStartIndex: metadata["next_start_index"] as Int)
        }
    }

    func replaceTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        try await databaseQueue.write { database in
            try Self.ensureScope(scope, libraryScope: libraryScope, in: database)
            try database.execute(sql: "DELETE FROM track_catalog_entries WHERE server_id = ? AND account_id = ? AND library_scope = ?", arguments: [scope.serverID, scope.accountID, libraryScope])
            try Self.writeTrackPage(page, generation: generation, scope: scope, libraryScope: libraryScope, in: database, replaceMetadata: true)
        }
    }

    func appendTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws {
        let libraryScope = Self.libraryScope(for: libraryID)
        try await databaseQueue.write { database in
            guard let stored: String = try String.fetchOne(database, sql: "SELECT generation FROM track_catalog_metadata WHERE server_id = ? AND account_id = ? AND library_scope = ?", arguments: [scope.serverID, scope.accountID, libraryScope]), stored == generation else { return }
            try Self.writeTrackPage(page, generation: generation, scope: scope, libraryScope: libraryScope, in: database, replaceMetadata: true)
        }
    }

    func enqueueFavourite(scope: LibraryScope, itemID: String, desired: Bool, sequence: Int64) async throws -> FavouriteMutation {
        let id = "favourite:\(scope.serverID):\(scope.accountID):\(itemID)"
        return try await databaseQueue.write { db in
            try Self.ensureScope(scope, libraryScope: Self.globalLibraryScope, in: db)
            try db.execute(sql: "INSERT INTO favourite_mutations (id,server_id,account_id,item_id,desired,sequence,attempts,next_retry_at,state) VALUES (?,?,?,?,?,?,0,0,'pending') ON CONFLICT(server_id,account_id,item_id) DO UPDATE SET desired=excluded.desired, sequence=excluded.sequence, attempts=0, next_retry_at=0, state='pending'", arguments: [id, scope.serverID, scope.accountID, itemID, desired ? 1 : 0, sequence])
            return FavouriteMutation(id: id, serverID: scope.serverID, accountID: scope.accountID, itemID: itemID, desired: desired, sequence: sequence, attempts: 0, nextRetryAt: 0, state: .pending)
        }
    }
    func pendingFavourites(scope: LibraryScope) async throws -> [FavouriteMutation] { try await databaseQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM favourite_mutations WHERE server_id=? AND account_id=? AND state != 'completed' ORDER BY sequence", arguments: [scope.serverID, scope.accountID]).compactMap(Self.mutation) } }
    func completeFavourite(_ mutation: FavouriteMutation) async throws { try await updateFavourite({ var x=mutation; x.state = .completed; return x }()) }
    func updateFavourite(_ m: FavouriteMutation) async throws { try await databaseQueue.write { db in try db.execute(sql: "UPDATE favourite_mutations SET desired=?, sequence=?, attempts=?, next_retry_at=?, state=? WHERE id=?", arguments: [m.desired ? 1:0,m.sequence,m.attempts,m.nextRetryAt,m.state.rawValue,m.id]) } }
    func enqueuePlaylistRename(scope: LibraryScope, playlistID: String, baseRevision: String, baseName: String, desiredName: String, sequence: Int64) async throws -> PlaylistRenameMutation {
        let desired = try PlaylistRenameValidation.validate(desiredName)
        let id = "playlist-rename:\(scope.serverID):\(scope.accountID):\(playlistID)"
        return try await databaseQueue.write { db in
            try Self.ensureScope(scope, libraryScope: Self.globalLibraryScope, in: db)
            try db.execute(sql: "INSERT INTO playlist_rename_mutations (id,server_id,account_id,playlist_id,base_revision,base_name,desired_name,sequence,attempts,next_retry_at,state) VALUES (?,?,?,?,?,?,?, ?,0,0,'pending') ON CONFLICT(server_id,account_id,playlist_id) DO UPDATE SET base_revision=excluded.base_revision,base_name=excluded.base_name,desired_name=excluded.desired_name,sequence=excluded.sequence,attempts=0,next_retry_at=0,state='pending'", arguments: [id,scope.serverID,scope.accountID,playlistID,baseRevision,baseName,desired,sequence])
            return PlaylistRenameMutation(id:id,serverID:scope.serverID,accountID:scope.accountID,playlistID:playlistID,baseRevision:baseRevision,baseName:baseName,desiredName:desired,sequence:sequence,attempts:0,nextRetryAt:0,state:.pending)
        }
    }
    func pendingPlaylistRenames(scope: LibraryScope) async throws -> [PlaylistRenameMutation] { try await databaseQueue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM playlist_rename_mutations WHERE server_id=? AND account_id=? AND state != 'completed' ORDER BY sequence", arguments: [scope.serverID,scope.accountID]).compactMap(Self.playlistRename) } }
    func updatePlaylistRename(_ m: PlaylistRenameMutation) async throws { try await databaseQueue.write { db in try db.execute(sql: "UPDATE playlist_rename_mutations SET base_revision=?,base_name=?,desired_name=?,sequence=?,attempts=?,next_retry_at=?,state=? WHERE id=?", arguments: [m.baseRevision,m.baseName,m.desiredName,m.sequence,m.attempts,m.nextRetryAt,m.state.rawValue,m.id]) } }
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
        migrator.registerMigration("003_create_track_catalog") { database in
            try database.execute(sql: """
                CREATE TABLE track_catalog_metadata (
                    server_id TEXT NOT NULL, account_id TEXT NOT NULL, library_scope TEXT NOT NULL,
                    generation TEXT NOT NULL, has_more INTEGER NOT NULL, next_start_index INTEGER NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope),
                    FOREIGN KEY (server_id, account_id, library_scope) REFERENCES library_scopes(server_id, account_id, library_scope) ON DELETE CASCADE
                ) WITHOUT ROWID;
                CREATE TABLE track_catalog_entries (
                    server_id TEXT NOT NULL, account_id TEXT NOT NULL, library_scope TEXT NOT NULL,
                    occurrence_id TEXT NOT NULL, ordinal INTEGER NOT NULL, payload BLOB NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope, occurrence_id),
                    FOREIGN KEY (server_id, account_id, library_scope) REFERENCES library_scopes(server_id, account_id, library_scope) ON DELETE CASCADE
                ) WITHOUT ROWID;
                CREATE INDEX track_catalog_entries_order ON track_catalog_entries(server_id, account_id, library_scope, ordinal);
                """)
        }
        migrator.registerMigration("004_create_track_favourite_outbox") { database in
            try database.execute(sql: "CREATE TABLE favourite_mutations (id TEXT PRIMARY KEY, server_id TEXT NOT NULL, account_id TEXT NOT NULL, item_id TEXT NOT NULL, desired INTEGER NOT NULL, sequence INTEGER NOT NULL, attempts INTEGER NOT NULL, next_retry_at INTEGER NOT NULL, state TEXT NOT NULL, UNIQUE(server_id, account_id, item_id))")
        }
        migrator.registerMigration("005_create_playlist_rename_outbox") { database in
            try database.execute(sql: "CREATE TABLE playlist_rename_mutations (id TEXT PRIMARY KEY, server_id TEXT NOT NULL, account_id TEXT NOT NULL, playlist_id TEXT NOT NULL, base_revision TEXT NOT NULL, base_name TEXT NOT NULL, desired_name TEXT NOT NULL, sequence INTEGER NOT NULL, attempts INTEGER NOT NULL, next_retry_at INTEGER NOT NULL, state TEXT NOT NULL, UNIQUE(server_id, account_id, playlist_id))")
        }
        migrator.registerMigration("006_add_album_sort_index") { database in
            // Preserves the server-received page order so the cache can present
            // the newest-first album shelf without reinterpreting it locally.
            try database.execute(sql: "ALTER TABLE cached_albums ADD COLUMN sort_index INTEGER NOT NULL DEFAULT 0")
        }
        migrator.registerMigration("007_create_detail_track_snapshots") { database in
            // Whole-container snapshots (album track lists, playlist entries)
            // so detail screens paint instantly across launches.
            try database.execute(sql: """
                CREATE TABLE detail_track_snapshots (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    container_id TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (server_id, account_id, library_scope, container_id),
                    FOREIGN KEY (server_id, account_id, library_scope)
                        REFERENCES library_scopes (server_id, account_id, library_scope)
                        ON DELETE CASCADE
                ) WITHOUT ROWID
                """)
        }
        migrator.registerMigration("008_create_downloaded_tracks") { database in
            // Offline manifest (ADR 0009): one verified record per downloaded
            // track, scoped by server/account. Downloads are user-global, so
            // no library_scope column.
            try database.execute(sql: """
                CREATE TABLE downloaded_tracks (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (server_id, account_id, item_id)
                ) WITHOUT ROWID
                """)
        }
        migrator.registerMigration("009_add_artist_sort_index") { database in
            // Preserves the server-received page order so the artist browse
            // list can present the server's SortName collation without
            // reinterpreting it locally.
            try database.execute(sql: "ALTER TABLE cached_artists ADD COLUMN sort_index INTEGER NOT NULL DEFAULT 0")
        }
        migrator.registerMigration("010_create_playlist_and_genre_caches") { database in
            // Browse caches for the remaining Library surfaces, shaped like
            // cached_albums: server-received order preserved via sort_index,
            // payload replaced in place on re-receipt.
            try database.execute(sql: """
                CREATE TABLE cached_playlists (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    sort_index INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (server_id, account_id, library_scope, item_id),
                    FOREIGN KEY (server_id, account_id, library_scope)
                        REFERENCES library_scopes (server_id, account_id, library_scope)
                        ON DELETE CASCADE
                ) WITHOUT ROWID;

                CREATE TABLE cached_genres (
                    server_id TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    library_scope TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    sort_index INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (server_id, account_id, library_scope, item_id),
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

    static func upsert(_ artist: Artist, sortIndex: Int, scope: LibraryScope, libraryScope: String, in database: Database) throws {
        let payload = try JSONEncoder().encode(artist)
        try database.execute(
            sql: """
                INSERT INTO cached_artists (server_id, account_id, library_scope, item_id, payload, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (server_id, account_id, library_scope, item_id)
                DO UPDATE SET payload = excluded.payload
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope, artist.id, payload, sortIndex]
        )
    }

    static func upsert(_ album: Album, sortIndex: Int, scope: LibraryScope, libraryScope: String, in database: Database) throws {
        let payload = try JSONEncoder().encode(album)
        try database.execute(
            sql: """
                INSERT INTO cached_albums (server_id, account_id, library_scope, item_id, payload, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (server_id, account_id, library_scope, item_id)
                DO UPDATE SET payload = excluded.payload
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope, album.id, payload, sortIndex]
        )
    }

    static func upsert(_ playlist: Playlist, sortIndex: Int, scope: LibraryScope, libraryScope: String, in database: Database) throws {
        let payload = try JSONEncoder().encode(playlist)
        try database.execute(
            sql: """
                INSERT INTO cached_playlists (server_id, account_id, library_scope, item_id, payload, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (server_id, account_id, library_scope, item_id)
                DO UPDATE SET payload = excluded.payload
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope, playlist.id, payload, sortIndex]
        )
    }

    static func upsert(_ genre: Genre, sortIndex: Int, scope: LibraryScope, libraryScope: String, in database: Database) throws {
        let payload = try JSONEncoder().encode(genre)
        try database.execute(
            sql: """
                INSERT INTO cached_genres (server_id, account_id, library_scope, item_id, payload, sort_index)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (server_id, account_id, library_scope, item_id)
                DO UPDATE SET payload = excluded.payload
                """,
            arguments: [scope.serverID, scope.accountID, libraryScope, genre.id, payload, sortIndex]
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

    static func playlist(from row: Row) -> Playlist? {
        guard let itemID: String = row["item_id"],
              let payload: Data = row["payload"],
              let playlist = try? JSONDecoder().decode(Playlist.self, from: payload),
              playlist.id == itemID,
              isValid(playlist)
        else { return nil }
        return playlist
    }

    static func genre(from row: Row) -> Genre? {
        guard let itemID: String = row["item_id"],
              let payload: Data = row["payload"],
              let genre = try? JSONDecoder().decode(Genre.self, from: payload),
              genre.id == itemID,
              isValid(genre)
        else { return nil }
        return genre
    }

    static func isValid(_ playlist: Playlist) -> Bool {
        !playlist.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isValid(_ genre: Genre) -> Bool {
        !genre.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !genre.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    static func mutation(from row: Row) -> FavouriteMutation? { guard let id: String=row["id"], let server: String=row["server_id"], let account: String=row["account_id"], let item: String=row["item_id"], let desired: Int=row["desired"], let sequence: Int64=row["sequence"], let attempts: Int=row["attempts"], let retry: Int64=row["next_retry_at"], let stateRaw: String=row["state"], let state=FavouriteMutationState(rawValue: stateRaw) else { return nil }; return FavouriteMutation(id:id,serverID:server,accountID:account,itemID:item,desired:desired == 1,sequence:sequence,attempts:attempts,nextRetryAt:retry,state:state) }
    static func playlistRename(from row: Row) -> PlaylistRenameMutation? {
        guard let id:String=row["id"], let serverID:String=row["server_id"], let accountID:String=row["account_id"], let playlistID:String=row["playlist_id"], let baseRevision:String=row["base_revision"], let baseName:String=row["base_name"], let desiredName:String=row["desired_name"], let sequence:Int64=row["sequence"], let attempts:Int=row["attempts"], let nextRetryAt:Int64=row["next_retry_at"], let raw:String=row["state"], let state=PlaylistRenameState(rawValue: raw) else { return nil }
        return PlaylistRenameMutation(id:id,serverID:serverID,accountID:accountID,playlistID:playlistID,baseRevision:baseRevision,baseName:baseName,desiredName:desiredName,sequence:sequence,attempts:attempts,nextRetryAt:nextRetryAt,state:state)
    }

    static func trackOccurrence(from row: Row) -> TrackCatalogOccurrence? {
        guard let id: String = row["occurrence_id"], let ordinal: Int = row["ordinal"], let payload: Data = row["payload"],
              let value = try? JSONDecoder().decode(TrackCatalogOccurrence.self, from: payload), value.id == id, value.ordinal == ordinal else { return nil }
        return value
    }

    static func writeTrackPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryScope: String, in database: Database, replaceMetadata: Bool) throws {
        for occurrence in page.occurrences {
            let payload = try JSONEncoder().encode(occurrence)
            try database.execute(sql: "INSERT OR REPLACE INTO track_catalog_entries(server_id, account_id, library_scope, occurrence_id, ordinal, payload) VALUES (?, ?, ?, ?, ?, ?)", arguments: [scope.serverID, scope.accountID, libraryScope, occurrence.id, occurrence.ordinal, payload])
        }
        guard replaceMetadata else { return }
        try database.execute(sql: "INSERT INTO track_catalog_metadata(server_id, account_id, library_scope, generation, has_more, next_start_index) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(server_id, account_id, library_scope) DO UPDATE SET generation = excluded.generation, has_more = excluded.has_more, next_start_index = excluded.next_start_index", arguments: [scope.serverID, scope.accountID, libraryScope, generation, page.hasMore ? 1 : 0, page.nextStartIndex])
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
