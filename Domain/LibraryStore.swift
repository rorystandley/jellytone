import Foundation

struct LibraryScope: Hashable, Sendable {
    let serverID: String
    let accountID: String
}

enum FavouriteMutationState: String, Codable, Sendable { case pending, pausedAuth, terminal, completed }
struct TrackFavouriteMutation: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let serverID: String
    let accountID: String
    let itemID: String
    let desired: Bool
    let sequence: Int64
    var attempts: Int
    var nextRetryAt: Int64
    var state: FavouriteMutationState
}
enum PlaylistRenameState: String, Codable, Sendable { case pending, pausedAuth, conflict, terminal, completed }
struct PlaylistRenameMutation: Codable, Hashable, Sendable, Identifiable {
    let id: String; let serverID: String; let accountID: String; let playlistID: String
    var baseRevision: String; var baseName: String
    var desiredName: String; var sequence: Int64; var attempts: Int; var nextRetryAt: Int64; var state: PlaylistRenameState
}
enum PlaylistRenameValidationError: Error, Equatable { case empty, controlCharacter, tooLong }
enum PlaylistRenameValidation {
    static let maximumLength = 255
    static func validate(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PlaylistRenameValidationError.empty }
        guard !name.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }) else { throw PlaylistRenameValidationError.controlCharacter }
        guard name.count <= maximumLength else { throw PlaylistRenameValidationError.tooLong }
        return name
    }
}

protocol LibraryStoring: Sendable {
    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album]
    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws
    /// Write-through cache for the Artists browse list, preserving the
    /// server-received SortName order so the next visit paints instantly.
    func cachedArtists(scope: LibraryScope, libraryID: String?) async throws -> [Artist]
    func replaceArtists(_ artists: [Artist], scope: LibraryScope, libraryID: String?) async throws
    func appendArtists(_ artists: [Artist], scope: LibraryScope, libraryID: String?) async throws
    /// Appends a further album page received while paginating, preserving the
    /// server-received order after the cached tail. Already-cached albums keep
    /// their position; only their payload refreshes.
    func appendAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws
    /// Whole-container detail snapshots so album/playlist screens paint
    /// instantly across launches; the network refresh replaces them silently.
    func cachedAlbumTracks(albumID: String, scope: LibraryScope, libraryID: String?) async throws -> [Track]?
    func replaceAlbumTracks(_ tracks: [Track], albumID: String, scope: LibraryScope, libraryID: String?) async throws
    func cachedPlaylistEntries(playlistID: String, scope: LibraryScope, libraryID: String?) async throws -> [PlaylistEntry]?
    func replacePlaylistEntries(_ entries: [PlaylistEntry], playlistID: String, scope: LibraryScope, libraryID: String?) async throws
    func cachedArtistAlbums(artistID: String, scope: LibraryScope, libraryID: String?) async throws -> [Album]?
    func replaceArtistAlbums(_ albums: [Album], artistID: String, scope: LibraryScope, libraryID: String?) async throws
    func cachedArtistTopTracks(artistID: String, scope: LibraryScope, libraryID: String?) async throws -> [Track]?
    func replaceArtistTopTracks(_ tracks: [Track], artistID: String, scope: LibraryScope, libraryID: String?) async throws
    /// Browse caches for the playlist and genre Library screens, shaped like
    /// the album cache: the first page replaces the snapshot, later pages
    /// append, so the screen paints instantly across launches.
    func cachedPlaylists(scope: LibraryScope, libraryID: String?) async throws -> [Playlist]
    func replacePlaylists(_ playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws
    func appendPlaylists(_ playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws
    func cachedGenres(scope: LibraryScope, libraryID: String?) async throws -> [Genre]
    func replaceGenres(_ genres: [Genre], scope: LibraryScope, libraryID: String?) async throws
    func appendGenres(_ genres: [Genre], scope: LibraryScope, libraryID: String?) async throws
    /// Genre detail snapshots (albums and tracks), like the artist-albums
    /// snapshot, so a genre screen paints from cache before the refresh lands.
    func cachedGenreAlbums(genreID: String, scope: LibraryScope, libraryID: String?) async throws -> [Album]?
    func replaceGenreAlbums(_ albums: [Album], genreID: String, scope: LibraryScope, libraryID: String?) async throws
    func cachedGenreTracks(genreID: String, scope: LibraryScope, libraryID: String?) async throws -> [GenreTrackOccurrence]?
    func replaceGenreTracks(_ occurrences: [GenreTrackOccurrence], genreID: String, scope: LibraryScope, libraryID: String?) async throws
    /// Offline download manifest (ADR 0009). Records are authoritative for
    /// source resolution; a file without a record is an orphan.
    func downloadedTracks(scope: LibraryScope) async throws -> [DownloadedTrack]
    func recordDownloadedTrack(_ record: DownloadedTrack, scope: LibraryScope) async throws
    func removeDownloadedTrack(itemID: String, scope: LibraryScope) async throws
    /// Returns the complete, versioned Home snapshot for this server/account/library
    /// scope. A missing or malformed record is treated as an unavailable cache.
    func cachedHomeShelfSnapshot(
        scope: LibraryScope,
        libraryID: String?
    ) async throws -> HomeShelfSnapshot?
    /// Replaces every Home shelf together so consumers never observe a mixed
    /// recently-added/recently-played generation.
    func replaceHomeShelfSnapshot(
        _ snapshot: HomeShelfSnapshot,
        scope: LibraryScope,
        libraryID: String?
    ) async throws
    func storeSearchMetadata(
        artists: [Artist],
        albums: [Album],
        scope: LibraryScope,
        libraryID: String?
    ) async throws
    func searchMusic(query: String, scope: LibraryScope, libraryID: String?) async throws -> MusicSearchPage
    func cachedTrackCatalogPage(scope: LibraryScope, libraryID: String?, limit: Int) async throws -> TrackCatalogPage?
    func replaceTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws
    func appendTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws
    func enqueueTrackFavourite(scope: LibraryScope, itemID: String, desired: Bool, sequence: Int64) async throws -> TrackFavouriteMutation
    func pendingTrackFavourites(scope: LibraryScope) async throws -> [TrackFavouriteMutation]
    func completeTrackFavourite(_ mutation: TrackFavouriteMutation) async throws
    func updateTrackFavourite(_ mutation: TrackFavouriteMutation) async throws
    func enqueuePlaylistRename(scope: LibraryScope, playlistID: String, baseRevision: String, baseName: String, desiredName: String, sequence: Int64) async throws -> PlaylistRenameMutation
    func pendingPlaylistRenames(scope: LibraryScope) async throws -> [PlaylistRenameMutation]
    func updatePlaylistRename(_ mutation: PlaylistRenameMutation) async throws
}

extension LibraryStoring {
    func appendAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws {}
    func cachedArtists(scope: LibraryScope, libraryID: String?) async throws -> [Artist] { [] }
    func replaceArtists(_ artists: [Artist], scope: LibraryScope, libraryID: String?) async throws {}
    func appendArtists(_ artists: [Artist], scope: LibraryScope, libraryID: String?) async throws {}
    func cachedAlbumTracks(albumID: String, scope: LibraryScope, libraryID: String?) async throws -> [Track]? { nil }
    func replaceAlbumTracks(_ tracks: [Track], albumID: String, scope: LibraryScope, libraryID: String?) async throws {}
    func cachedPlaylistEntries(playlistID: String, scope: LibraryScope, libraryID: String?) async throws -> [PlaylistEntry]? { nil }
    func replacePlaylistEntries(_ entries: [PlaylistEntry], playlistID: String, scope: LibraryScope, libraryID: String?) async throws {}
    func cachedArtistAlbums(artistID: String, scope: LibraryScope, libraryID: String?) async throws -> [Album]? { nil }
    func replaceArtistAlbums(_ albums: [Album], artistID: String, scope: LibraryScope, libraryID: String?) async throws {}
    func cachedArtistTopTracks(artistID: String, scope: LibraryScope, libraryID: String?) async throws -> [Track]? { nil }
    func replaceArtistTopTracks(_ tracks: [Track], artistID: String, scope: LibraryScope, libraryID: String?) async throws {}
    func cachedPlaylists(scope: LibraryScope, libraryID: String?) async throws -> [Playlist] { [] }
    func replacePlaylists(_ playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws {}
    func appendPlaylists(_ playlists: [Playlist], scope: LibraryScope, libraryID: String?) async throws {}
    func cachedGenres(scope: LibraryScope, libraryID: String?) async throws -> [Genre] { [] }
    func replaceGenres(_ genres: [Genre], scope: LibraryScope, libraryID: String?) async throws {}
    func appendGenres(_ genres: [Genre], scope: LibraryScope, libraryID: String?) async throws {}
    func cachedGenreAlbums(genreID: String, scope: LibraryScope, libraryID: String?) async throws -> [Album]? { nil }
    func replaceGenreAlbums(_ albums: [Album], genreID: String, scope: LibraryScope, libraryID: String?) async throws {}
    func cachedGenreTracks(genreID: String, scope: LibraryScope, libraryID: String?) async throws -> [GenreTrackOccurrence]? { nil }
    func replaceGenreTracks(_ occurrences: [GenreTrackOccurrence], genreID: String, scope: LibraryScope, libraryID: String?) async throws {}
    func downloadedTracks(scope: LibraryScope) async throws -> [DownloadedTrack] { [] }
    func recordDownloadedTrack(_ record: DownloadedTrack, scope: LibraryScope) async throws {}
    func removeDownloadedTrack(itemID: String, scope: LibraryScope) async throws {}
    func cachedTrackCatalogPage(scope: LibraryScope, libraryID: String?, limit: Int) async throws -> TrackCatalogPage? { nil }
    func replaceTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws {}
    func appendTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws {}
    func enqueueTrackFavourite(scope: LibraryScope, itemID: String, desired: Bool, sequence: Int64) async throws -> TrackFavouriteMutation { fatalError("Store does not support mutations") }
    func pendingTrackFavourites(scope: LibraryScope) async throws -> [TrackFavouriteMutation] { [] }
    func completeTrackFavourite(_ mutation: TrackFavouriteMutation) async throws {}
    func updateTrackFavourite(_ mutation: TrackFavouriteMutation) async throws {}
    func enqueuePlaylistRename(scope: LibraryScope, playlistID: String, baseRevision: String, baseName: String, desiredName: String, sequence: Int64) async throws -> PlaylistRenameMutation { fatalError("Store does not support playlist renames") }
    func pendingPlaylistRenames(scope: LibraryScope) async throws -> [PlaylistRenameMutation] { [] }
    func updatePlaylistRename(_ mutation: PlaylistRenameMutation) async throws {}
}
