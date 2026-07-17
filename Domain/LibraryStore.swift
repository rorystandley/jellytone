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

protocol LibraryStoring: Sendable {
    func cachedAlbums(scope: LibraryScope, libraryID: String?) async throws -> [Album]
    func replaceAlbums(_ albums: [Album], scope: LibraryScope, libraryID: String?) async throws
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
}

extension LibraryStoring {
    func cachedTrackCatalogPage(scope: LibraryScope, libraryID: String?, limit: Int) async throws -> TrackCatalogPage? { nil }
    func replaceTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws {}
    func appendTrackCatalogPage(_ page: TrackCatalogPage, generation: String, scope: LibraryScope, libraryID: String?) async throws {}
    func enqueueTrackFavourite(scope: LibraryScope, itemID: String, desired: Bool, sequence: Int64) async throws -> TrackFavouriteMutation { fatalError("Store does not support mutations") }
    func pendingTrackFavourites(scope: LibraryScope) async throws -> [TrackFavouriteMutation] { [] }
    func completeTrackFavourite(_ mutation: TrackFavouriteMutation) async throws {}
    func updateTrackFavourite(_ mutation: TrackFavouriteMutation) async throws {}
}
